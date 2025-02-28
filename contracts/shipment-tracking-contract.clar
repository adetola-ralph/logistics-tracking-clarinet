;; Logistics Tracking Smart Contract with Enhanced Security

;; Shipment status constants
(define-constant STATUS-PENDING u0)
(define-constant STATUS-IN-TRANSIT u1)
(define-constant STATUS-DELIVERED u2)
(define-constant STATUS-DISPUTED u3)
(define-constant STATUS-CANCELLED u4)  ;; New status for cancelled shipments

;; Error constants for precise error handling
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-SHIPMENT-NOT-FOUND (err u101))
(define-constant ERR-INVALID-STATUS (err u102))
(define-constant ERR-DISPUTE-PERIOD-NOT-ELAPSED (err u103))
(define-constant ERR-INVALID-SHIPMENT-ID (err u104))
(define-constant ERR-INVALID-FEE (err u105))
(define-constant ERR-DUPLICATE-SHIPMENT (err u106))
(define-constant ERR-ALREADY-DISPUTED (err u107))
(define-constant ERR-DISPUTE-NOT-FOUND (err u108))
(define-constant ERR-PAYMENT-FAILED (err u109))
(define-constant ERR-INVALID-MILESTONE (err u110))

;; Contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; Shipment record structure
(define-map shipments uint {
  sender: principal,
  recipient: principal,
  carrier: principal,
  origin: (string-ascii 50),
  destination: (string-ascii 50),
  fee: uint,
  status: uint,
  creation-time: uint,
  dispute-period: uint
})

;; Dispute tracking map
(define-map disputes uint {
  shipment-id: uint,
  dispute-initiator: principal,
  dispute-reason: (string-ascii 100),
  resolution-status: (string-ascii 20)
})

;; Validate shipment creation inputs
(define-private (validate-shipment-inputs 
  (shipment-id uint)
  (recipient principal)
  (carrier principal)
  (origin (string-ascii 50))
  (destination (string-ascii 50))
  (fee uint)
  (dispute-period uint)
)
  (begin
    ;; Check that shipment ID doesn't already exist
    (asserts! (is-none (map-get? shipments shipment-id)) ERR-DUPLICATE-SHIPMENT)
    
    ;; Validate fee is greater than zero
    (asserts! (> fee u0) ERR-INVALID-FEE)
    
    ;; Ensure recipient is not the sender
    (asserts! (not (is-eq tx-sender recipient)) ERR-UNAUTHORIZED)
    
    ;; Ensure carrier is different from sender and recipient
    (asserts! 
      (and 
        (not (is-eq tx-sender carrier)) 
        (not (is-eq recipient carrier))
      ) 
      ERR-UNAUTHORIZED
    )
    
    ;; Validate origin and destination are not empty
    (asserts! (> (len origin) u0) ERR-INVALID-SHIPMENT-ID)
    (asserts! (> (len destination) u0) ERR-INVALID-SHIPMENT-ID)
    
    ;; Validate dispute period
    (asserts! (> dispute-period u0) ERR-INVALID-SHIPMENT-ID)
    
    (ok true)
  )
)

;; Create a new shipment contract
(define-public (create-shipment
  (shipment-id uint)
  (recipient principal)
  (carrier principal)
  (origin (string-ascii 50))
  (destination (string-ascii 50))
  (fee uint)
  (dispute-period uint)
)
  (begin
    ;; Validate inputs first
    (try! (validate-shipment-inputs 
      shipment-id recipient carrier origin destination fee dispute-period))
    
    ;; Transfer fee to contract as escrow
    (try! (stx-transfer? fee tx-sender (as-contract tx-sender)))
    
    ;; Store shipment details
    (map-insert shipments shipment-id {
      sender: tx-sender,
      recipient: recipient,
      carrier: carrier,
      origin: origin,
      destination: destination,
      fee: fee,
      status: STATUS-PENDING,
      creation-time: u0,  ;; Placeholder for creation time
      dispute-period: dispute-period
    })
    
    (ok true)
  )
)

;; Update shipment status with enhanced validation
(define-public (update-shipment-status 
  (shipment-id uint)
  (new-status uint)
)
  (match (map-get? shipments shipment-id)
    shipment
    (begin
      ;; Validate status transitions
      (asserts! 
        (or
          ;; Carrier can move from PENDING to IN-TRANSIT
          (and 
            (is-eq (get status shipment) STATUS-PENDING)
            (is-eq new-status STATUS-IN-TRANSIT)
            (is-eq tx-sender (get carrier shipment))
          )
          ;; Recipient can move to DELIVERED
          (and
            (is-eq (get status shipment) STATUS-IN-TRANSIT)
            (is-eq new-status STATUS-DELIVERED)
            (is-eq tx-sender (get recipient shipment))
          )
        )
        ERR-UNAUTHORIZED
      )
      
      ;; Update shipment status
      (map-set shipments shipment-id 
        (merge shipment { status: new-status }))
      
      (ok true)
    )
    ERR-SHIPMENT-NOT-FOUND
  )
)

