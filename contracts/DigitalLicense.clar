;; Import SIP-010 trait
(use-trait ft-trait 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)

;; Define a constant for the sBTC token contract
(define-constant sbTC-token 'SP3DX3H4FEYZJZ586MFBS25ZW3HZDMEW92260R2PR.Wrapped-Bitcoin)

;; Update content structure to use sBTC for pricing
(define-map contents
  { content-id: uint }
  {
    creator: principal,
    title: (string-ascii 50),
    content-type: (string-ascii 10),
    base-price: uint,
    premium-price: uint,
    license-terms: (string-ascii 200),
    metadata: (string-utf8 500),
    total-earnings: uint
  }
)

;; Function to add new content with sBTC pricing
(define-public (add-content (title (string-ascii 50)) (content-type (string-ascii 10)) (base-price uint) (premium-price uint) (license-terms (string-ascii 200)) (metadata (string-utf8 500)))
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
        base-price: base-price,
        premium-price: premium-price,
        license-terms: license-terms,
        metadata: metadata,
        total-earnings: u0
      }
    )
    (var-set content-counter content-id)
    (ok content-id)
  )
)

;; Function to purchase a license using sBTC
(define-public (purchase-license-with-sbtc (content-id uint) (tier (string-ascii 10)) (sbtc-token <ft-trait>))
  (let
    (
      (content (unwrap! (map-get? contents { content-id: content-id }) (err u404)))
      (price (if (is-eq tier "premium") (get premium-price content) (get base-price content)))
      (creator (get creator content))
    )
    (asserts! (is-eq (contract-of sbtc-token) sbTC-token) (err u403))
    (if (is-eq tx-sender creator)
      (err u403)
      (match (contract-call? sbtc-token transfer price tx-sender (as-contract tx-sender) none)
        success
          (let
            (
              (license-id (+ (var-get content-counter) u1))
            )
            (try! (distribute-royalties-sbtc content-id price sbtc-token))
            (map-set licenses
              { license-id: license-id }
              {
                content-id: content-id,
                licensee: tx-sender,
                expiration: (+ block-height u52560), ;; License valid for ~1 year (assuming 10-minute blocks)
                tier: tier
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

;; Function to distribute royalties using sBTC
(define-private (distribute-royalties-sbtc (content-id uint) (amount uint) (sbtc-token <ft-trait>))
  (match (map-get? royalty-recipients { content-id: content-id })
    recipients
      (fold distribute-to-recipient-sbtc (get recipients recipients) (ok amount))
    (err u404)
  )
)

(define-private (distribute-to-recipient-sbtc (recipient { address: principal, share: uint }) (remaining uint))
  (let
    (
      (amount-to-send (/ (* (get remaining remaining) (get share recipient)) u100))
    )
    (match (contract-call? sbtc-token transfer amount-to-send (as-contract tx-sender) (get address recipient) none)
      success (ok (- remaining amount-to-send))
      error (err error)
    )
  )
)

;; Function to withdraw sBTC earnings
(define-public (withdraw-earnings (sbtc-token <ft-trait>))
  (let
    (
      (balance (unwrap! (contract-call? sbtc-token get-balance (as-contract tx-sender)) (err u500)))
    )
    (asserts! (> balance u0) (err u400))
    (match (contract-call? sbtc-token transfer balance (as-contract tx-sender) tx-sender none)
      success (ok balance)
      error (err error)
    )
  )
)

;; ... [Rest of the previous contract code remains unchanged]