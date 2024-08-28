;; Define the content structure
(define-data-var content-counter uint u0)

(define-map contents
  { content-id: uint }
  {
    creator: principal,
    title: (string-ascii 50),
    content-type: (string-ascii 10),
    price: uint,
    license-terms: (string-ascii 200)
  }
)

;; Define the license structure
(define-map licenses
  { license-id: uint }
  {
    content-id: uint,
    licensee: principal,
    expiration: uint
  }
)

;; Function to add new content
(define-public (add-content (title (string-ascii 50)) (content-type (string-ascii 10)) (price uint) (license-terms (string-ascii 200)))
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
        license-terms: license-terms
      }
    )
    (var-set content-counter content-id)
    (ok content-id)
  )
)

;; Function to purchase a license
(define-public (purchase-license (content-id uint))
  (let
    (
      (content (unwrap! (map-get? contents { content-id: content-id }) (err u404)))
      (price (get price content))
    )
    (if (is-eq tx-sender (get creator content))
      (err u403)
      (match (stx-transfer? price tx-sender (get creator content))
        success
          (let
            (
              (license-id (+ (var-get content-counter) u1))
            )
            (map-set licenses
              { license-id: license-id }
              {
                content-id: content-id,
                licensee: tx-sender,
                expiration: (+ block-height u52560) ;; License valid for ~1 year (assuming 10-minute blocks)
              }
            )
            (var-set content-counter license-id)
            (ok license-id)
          )
        error (err error)
      )
    )
  )
)

;; Function to check license validity
(define-read-only (is-license-valid (license-id uint))
  (match (map-get? licenses { license-id: license-id })
    license (ok (< block-height (get expiration license)))
    (err u404)
  )
)