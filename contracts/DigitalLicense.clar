;; Define the content structure
(define-data-var content-counter uint u0)

(define-map contents
  { content-id: uint }
  {
    creator: principal,
    title: (string-ascii 50),
    content-type: (string-ascii 10),
    price: uint,
    license-terms: (string-ascii 200),
    royalty-rate: uint,
    total-earnings: uint
  }
)

;; Define the license structure
(define-map licenses
  { license-id: uint }
  {
    content-id: uint,
    licensee: principal,
    expiration: uint,
    usage-count: uint
  }
)

;; Define royalty recipients
(define-map royalty-recipients
  { content-id: uint }
  { recipients: (list 10 principal) }
)

;; Function to add new content
(define-public (add-content (title (string-ascii 50)) (content-type (string-ascii 10)) (price uint) (license-terms (string-ascii 200)) (royalty-rate uint))
  (let
    (
      (content-id (+ (var-get content-counter) u1))
    )
    (map-set contents
      { content-id: content-id }
      {
        creator: tx-sender,
        title: title,
        content-type: content-type,
        price: price,
        license-terms: license-terms,
        royalty-rate: royalty-rate,
        total-earnings: u0
      }
    )
    (var-set content-counter content-id)
    (ok content-id)
  )
)

;; Function to set royalty recipients
(define-public (set-royalty-recipients (content-id uint) (recipients (list 10 principal)))
  (let
    (
      (content (unwrap! (map-get? contents { content-id: content-id }) (err u404)))
    )
    (asserts! (is-eq tx-sender (get creator content)) (err u403))
    (ok (map-set royalty-recipients { content-id: content-id } { recipients: recipients }))
  )
)

;; Function to purchase a license
(define-public (purchase-license (content-id uint))
  (let
    (
      (content (unwrap! (map-get? contents { content-id: content-id }) (err u404)))
      (price (get price content))
      (royalty-rate (get royalty-rate content))
      (creator (get creator content))
      (royalty-amount (/ (* price royalty-rate) u100))
      (creator-amount (- price royalty-amount))
    )
    (if (is-eq tx-sender creator)
      (err u403)
      (match (stx-transfer? price tx-sender (as-contract tx-sender))
        success
          (let
            (
              (license-id (+ (var-get content-counter) u1))
            )
            (try! (distribute-royalties content-id royalty-amount))
            (try! (stx-transfer? creator-amount (as-contract tx-sender) creator))
            (map-set licenses
              { license-id: license-id }
              {
                content-id: content-id,
                licensee: tx-sender,
                expiration: (+ block-height u52560), ;; License valid for ~1 year (assuming 10-minute blocks)
                usage-count: u0
              }
            )
            (map-set contents
              { content-id: content-id }
              (merge content { total-earnings: (+ (get total-earnings content) price) })
            )
            (var-set content-counter license-id)
            (ok license-id)
          )
        error (err error)
      )
    )
  )
)

;; Function to distribute royalties
(define-private (distribute-royalties (content-id uint) (royalty-amount uint))
  (match (map-get? royalty-recipients { content-id: content-id })
    recipients 
      (let
        (
          (recipient-count (len (get recipients recipients)))
          (amount-per-recipient (/ royalty-amount recipient-count))
        )
        (ok (map distribute-to-recipient (get recipients recipients)))
      )
    (err u404)
  )
)

;; Helper function to distribute to a single recipient
(define-private (distribute-to-recipient (recipient principal))
  (stx-transfer? amount-per-recipient (as-contract tx-sender) recipient)
)

;; Function to check license validity
(define-read-only (is-license-valid (license-id uint))
  (match (map-get? licenses { license-id: license-id })
    license (ok (< block-height (get expiration license)))
    (err u404)
  )
)

;; Function to record content usage
(define-public (record-usage (license-id uint))
  (match (map-get? licenses { license-id: license-id })
    license 
      (begin
        (asserts! (< block-height (get expiration license)) (err u401))
        (ok (map-set licenses 
          { license-id: license-id }
          (merge license { usage-count: (+ (get usage-count license) u1) })
        ))
      )
    (err u404)
  )
)

;; Function to get content usage analytics
(define-read-only (get-content-analytics (content-id uint))
  (match (map-get? contents { content-id: content-id })
    content 
      (ok {
        total-earnings: (get total-earnings content),
        license-count: (fold + (map get-license-count-for-content (keys licenses)) u0)
      })
    (err u404)
  )
)

;; Helper function to count licenses for a specific content
(define-private (get-license-count-for-content (license-id uint))
  (match (map-get? licenses { license-id: license-id })
    license (if (is-eq (get content-id license) content-id) u1 u0)
    u0
  )
)