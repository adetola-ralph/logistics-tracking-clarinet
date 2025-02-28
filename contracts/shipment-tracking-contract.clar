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

;; Tracking updates map - stores multiple updates per shipment
(define-map tracking-updates (tuple (shipment-id uint) (update-id uint)) {
  timestamp: uint,
  location: (string-ascii 50),
  description: (string-ascii 100),
  updated-by: principal
})

;; Counter for tracking updates
(define-map shipment-update-counters uint uint)

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
    
    ;; Get current block time
    (let ((current-time block-height))
      ;; Store shipment details
      (map-insert shipments shipment-id {
        sender: tx-sender,
        recipient: recipient,
        carrier: carrier,
        origin: origin,
        destination: destination,
        fee: fee,
        status: STATUS-PENDING,
        creation-time: current-time,
        last-updated: current-time,
        dispute-period: dispute-period
      })
      
      ;; Initialize tracking update counter
      (map-insert shipment-update-counters shipment-id u0)
      
      ;; Add initial tracking update
      (try! (add-tracking-update shipment-id origin "Shipment created and pending pickup"))
      
      (ok true)
    )
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
          ;; Contract owner can set any status (for administrative purposes)
          (is-eq tx-sender CONTRACT-OWNER)
        )
        ERR-UNAUTHORIZED
      )
      
      ;; Update shipment status
      (map-set shipments shipment-id 
        (merge shipment { 
          status: new-status,
          last-updated: block-height
        }))
      
      ;; If delivered, automatically release payment to carrier
      (if (is-eq new-status STATUS-DELIVERED)
          (try! (release-payment shipment-id))
          (ok true))
    )
    ERR-SHIPMENT-NOT-FOUND
  )
)

;; Release payment to carrier after successful delivery
(define-private (release-payment (shipment-id uint))
  (match (map-get? shipments shipment-id)
    shipment
    (begin
      ;; Ensure shipment is in DELIVERED status
      (asserts! (is-eq (get status shipment) STATUS-DELIVERED) ERR-INVALID-STATUS)
      
      ;; Transfer fee from contract to carrier
      (as-contract 
        (stx-transfer? 
          (get fee shipment) 
          tx-sender 
          (get carrier shipment)
        )
      )
    )
    ERR-SHIPMENT-NOT-FOUND
  )
)

;; Add tracking update for a shipment
(define-public (add-tracking-update
  (shipment-id uint)
  (location (string-ascii 50))
  (description (string-ascii 100))
)
  (match (map-get? shipments shipment-id)
    shipment
    (begin
      ;; Only carrier, sender, or contract owner can add updates
      (asserts! 
        (or 
          (is-eq tx-sender (get carrier shipment))
          (is-eq tx-sender (get sender shipment))
          (is-eq tx-sender CONTRACT-OWNER)
        ) 
        ERR-UNAUTHORIZED
      )
      
      ;; Get and increment update counter
      (match (map-get? shipment-update-counters shipment-id)
        counter
        (let ((new-counter (+ counter u1)))
          ;; Update counter
          (map-set shipment-update-counters shipment-id new-counter)
          
          ;; Add tracking update
          (map-insert 
            tracking-updates 
            (tuple (shipment-id shipment-id) (update-id counter))
            {
              timestamp: block-height,
              location: location,
              description: description,
              updated-by: tx-sender
            }
          )
          
          ;; Update last-updated timestamp in shipment
          (map-set shipments shipment-id 
            (merge shipment { last-updated: block-height }))
          
          (ok counter)
        )
        ERR-SHIPMENT-NOT-FOUND
      )
    )
    ERR-SHIPMENT-NOT-FOUND
  )
)

;; Initiate a dispute for a shipment
(define-public (initiate-dispute
  (shipment-id uint)
  (dispute-reason (string-ascii 100))
)
  (match (map-get? shipments shipment-id)
    shipment
    (begin
      ;; Only sender or recipient can initiate disputes
      (asserts! 
        (or 
          (is-eq tx-sender (get sender shipment))
          (is-eq tx-sender (get recipient shipment))
        ) 
        ERR-UNAUTHORIZED
      )
      
      ;; Ensure shipment is not already in disputed status
      (asserts! (not (is-eq (get status shipment) STATUS-DISPUTED)) ERR-ALREADY-DISPUTED)
      
      ;; Update shipment status to DISPUTED
      (map-set shipments shipment-id 
        (merge shipment { 
          status: STATUS-DISPUTED,
          last-updated: block-height
        }))
      
      ;; Create dispute record
      (map-insert disputes shipment-id {
        shipment-id: shipment-id,
        dispute-initiator: tx-sender,
        dispute-reason: dispute-reason,
        resolution-status: "pending",
        created-at: block-height,
        resolved-at: u0
      })
      
      ;; Add tracking update for dispute
      (try! (add-tracking-update 
        shipment-id 
        "Dispute Center" 
        (concat "Dispute initiated: " dispute-reason)))
      
      (ok true)
    )
    ERR-SHIPMENT-NOT-FOUND
  )
)

;; Resolve a dispute (only contract owner can do this)
(define-public (resolve-dispute
  (shipment-id uint)
  (resolution-status (string-ascii 20))
  (refund-percentage uint)
)
  (begin
    ;; Only contract owner can resolve disputes
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    
    ;; Check if dispute exists
    (match (map-get? disputes shipment-id)
      dispute
      (begin
        ;; Get shipment details
        (match (map-get? shipments shipment-id)
          shipment
          (begin
            ;; Ensure shipment is in DISPUTED status
            (asserts! (is-eq (get status shipment) STATUS-DISPUTED) ERR-INVALID-STATUS)
            
            ;; Update dispute record
            (map-set disputes shipment-id 
              (merge dispute { 
                resolution-status: resolution-status,
                resolved-at: block-height
              }))
            
            ;; Calculate refund amount
            (let ((refund-amount (/ (* (get fee shipment) refund-percentage) u100)))
              ;; Transfer refund to sender if applicable
              (if (> refund-amount u0)
                  (as-contract 
                    (stx-transfer? 
                      refund-amount 
                      tx-sender 
                      (get sender shipment)
                    )
                  )
                  (ok true))
              
              ;; Transfer remaining amount to carrier
              (let ((carrier-amount (- (get fee shipment) refund-amount)))
                (if (> carrier-amount u0)
                    (as-contract 
                      (stx-transfer? 
                        carrier-amount 
                        tx-sender 
                        (get carrier shipment)
                      )
                    )
                    (ok true))
                
                ;; Add tracking update for resolution
                (try! (add-tracking-update 
                  shipment-id 
                  "Dispute Center" 
                  (concat "Dispute resolved: " resolution-status)))
                
                (ok true)
              )
            )
          )
          ERR-SHIPMENT-NOT-FOUND
        )
      )
      ERR-DISPUTE-NOT-FOUND
    )
  )
)

;; Cancel a shipment (only sender can cancel, and only if status is PENDING)
(define-public (cancel-shipment (shipment-id uint))
  (match (map-get? shipments shipment-id)
    shipment
    (begin
      ;; Only sender can cancel shipment
      (asserts! (is-eq tx-sender (get sender shipment)) ERR-UNAUTHORIZED)
      
      ;; Ensure shipment is in PENDING status
      (asserts! (is-eq (get status shipment) STATUS-PENDING) ERR-INVALID-STATUS)
      
      ;; Update shipment status to CANCELLED
      (map-set shipments shipment-id 
        (merge shipment { 
          status: STATUS-CANCELLED,
          last-updated: block-height
        }))
      
      ;; Refund fee to sender
      (as-contract 
        (stx-transfer? 
          (get fee shipment) 
          tx-sender 
          (get sender shipment)
        )
      )
      
      ;; Add tracking update for cancellation
      (try! (add-tracking-update 
        shipment-id 
        (get origin shipment) 
        "Shipment cancelled by sender"))
      
      (ok true)
    )
    ERR-SHIPMENT-NOT-FOUND
  )
)

;; Get shipment details (read-only function)
(define-read-only (get-shipment-details (shipment-id uint))
  (match (map-get? shipments shipment-id)
    shipment (ok shipment)
    ERR-SHIPMENT-NOT-FOUND
  )
)

;; Get dispute details (read-only function)
(define-read-only (get-dispute-details (shipment-id uint))
  (match (map-get? disputes shipment-id)
    dispute (ok dispute)
    ERR-DISPUTE-NOT-FOUND
  )
)

;; Get tracking update (read-only function)
(define-read-only (get-tracking-update (shipment-id uint) (update-id uint))
  (match (map-get? tracking-updates (tuple (shipment-id shipment-id) (update-id update-id)))
    update (ok update)
    (err ERR-INVALID-MILESTONE)
  )
)

;; Get all tracking updates for a shipment (read-only function)
(define-read-only (get-tracking-update-count (shipment-id uint))
  (match (map-get? shipment-update-counters shipment-id)
    counter (ok counter)
    (err ERR-SHIPMENT-NOT-FOUND)
  )
)

