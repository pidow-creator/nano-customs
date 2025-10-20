;; NanoCustoms - Blockchain Customs Management System
;; A simplified implementation focusing on core customs operations

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-invalid-status (err u104))

;; Data Variables
(define-data-var customs-fee-rate uint u100) ;; Base fee in basis points (1% = 100)

;; Data Maps
(define-map shipments
    { shipment-id: uint }
    {
        importer: principal,
        exporter: principal,
        customs-authority: principal,
        product-hash: (buff 32),
        declared-value: uint,
        duty-amount: uint,
        status: (string-ascii 20),
        timestamp: uint
    }
)

(define-map customs-authorities
    { authority: principal }
    { 
        country-code: (string-ascii 3),
        authorized: bool,
        reputation-score: uint
    }
)

(define-map compliance-records
    { shipment-id: uint }
    {
        verified: bool,
        verified-by: principal,
        verification-timestamp: uint,
        risk-score: uint
    }
)

(define-map user-reputation
    { user: principal }
    { score: uint }
)

;; Counter for shipment IDs
(define-data-var shipment-counter uint u0)

;; Private Functions
(define-private (calculate-duty (declared-value uint))
    (/ (* declared-value (var-get customs-fee-rate)) u10000)
)

;; Public Functions

;; Register a customs authority
(define-public (register-customs-authority (authority principal) (country-code (string-ascii 3)))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set customs-authorities
            { authority: authority }
            {
                country-code: country-code,
                authorized: true,
                reputation-score: u100
            }
        ))
    )
)

;; Create a new shipment declaration
(define-public (create-shipment 
    (exporter principal)
    (customs-authority principal)
    (product-hash (buff 32))
    (declared-value uint))
    (let
        (
            (new-shipment-id (+ (var-get shipment-counter) u1))
            (duty (calculate-duty declared-value))
        )
        (asserts! (is-some (map-get? customs-authorities { authority: customs-authority })) err-unauthorized)
        (map-set shipments
            { shipment-id: new-shipment-id }
            {
                importer: tx-sender,
                exporter: exporter,
                customs-authority: customs-authority,
                product-hash: product-hash,
                declared-value: declared-value,
                duty-amount: duty,
                status: "pending",
                timestamp: block-height
            }
        )
        (var-set shipment-counter new-shipment-id)
        (ok new-shipment-id)
    )
)

;; Verify and approve shipment (customs authority only)
(define-public (verify-shipment (shipment-id uint) (risk-score uint))
    (let
        (
            (shipment (unwrap! (map-get? shipments { shipment-id: shipment-id }) err-not-found))
            (authority-data (unwrap! (map-get? customs-authorities { authority: tx-sender }) err-unauthorized))
        )
        (asserts! (get authorized authority-data) err-unauthorized)
        (asserts! (is-eq (get customs-authority shipment) tx-sender) err-unauthorized)
        (map-set shipments
            { shipment-id: shipment-id }
            (merge shipment { status: "verified" })
        )
        (map-set compliance-records
            { shipment-id: shipment-id }
            {
                verified: true,
                verified-by: tx-sender,
                verification-timestamp: block-height,
                risk-score: risk-score
            }
        )
        ;; Update reputation for importer
        (update-reputation (get importer shipment) u10)
        (ok true)
    )
)

;; Reject shipment
(define-public (reject-shipment (shipment-id uint) (reason (string-ascii 100)))
    (let
        (
            (shipment (unwrap! (map-get? shipments { shipment-id: shipment-id }) err-not-found))
            (authority-data (unwrap! (map-get? customs-authorities { authority: tx-sender }) err-unauthorized))
        )
        (asserts! (get authorized authority-data) err-unauthorized)
        (asserts! (is-eq (get customs-authority shipment) tx-sender) err-unauthorized)
        (map-set shipments
            { shipment-id: shipment-id }
            (merge shipment { status: "rejected" })
        )
        ;; Decrease reputation for importer
        (update-reputation (get importer shipment) u5)
        (ok true)
    )
)

;; Update user reputation
(define-private (update-reputation (user principal) (points uint))
    (let
        (
            (current-rep (default-to { score: u50 } (map-get? user-reputation { user: user })))
            (new-score (+ (get score current-rep) points))
        )
        (map-set user-reputation
            { user: user }
            { score: new-score }
        )
    )
)

;; Update customs fee rate (owner only)
(define-public (update-fee-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set customs-fee-rate new-rate)
        (ok true)
    )
)

;; Read-only functions

(define-read-only (get-shipment (shipment-id uint))
    (map-get? shipments { shipment-id: shipment-id })
)

(define-read-only (get-compliance-record (shipment-id uint))
    (map-get? compliance-records { shipment-id: shipment-id })
)

(define-read-only (get-authority-info (authority principal))
    (map-get? customs-authorities { authority: authority })
)

(define-read-only (get-user-reputation (user principal))
    (default-to { score: u50 } (map-get? user-reputation { user: user }))
)

(define-read-only (get-current-fee-rate)
    (var-get customs-fee-rate)
)

(define-read-only (get-shipment-count)
    (var-get shipment-counter)
)