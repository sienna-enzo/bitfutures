;; BitFutures: Decentralized Bitcoin Price Prediction Market

;; Constants
(define-constant contract-owner tx-sender) ;; The owner of the contract
(define-constant err-owner-only (err u100)) ;; Error code for owner-only actions
(define-constant err-not-found (err u101)) ;; Error code for not found
(define-constant err-invalid-prediction (err u102)) ;; Error code for invalid prediction
(define-constant err-market-closed (err u103)) ;; Error code for closed market
(define-constant err-already-claimed (err u104)) ;; Error code for already claimed winnings
(define-constant err-insufficient-balance (err u105)) ;; Error code for insufficient balance
(define-constant err-invalid-parameter (err u106)) ;; Error code for invalid parameter

;; Data variables
(define-data-var oracle-address principal 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM) ;; Address of the oracle
(define-data-var minimum-stake uint u1000000) ;; Minimum stake amount (1 STX)
(define-data-var fee-percentage uint u2) ;; Fee percentage (2%)
(define-data-var market-counter uint u0) ;; Counter for market IDs

;; Maps
(define-map markets
  uint
  {
    start-price: uint,
    end-price: uint,
    total-up-stake: uint,
    total-down-stake: uint,
    start-block: uint,
    end-block: uint,
    resolved: bool ;; Whether the market has been resolved
  }
)

(define-map user-predictions
  {market-id: uint, user: principal}
  {prediction: (string-ascii 4), stake: uint, claimed: bool} ;; User's prediction details
)

;; Public functions

;; Create a new market
(define-public (create-market (start-price uint) (start-block uint) (end-block uint))
  (let
    (
      (market-id (var-get market-counter)) ;; Get the current market counter
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only) ;; Ensure only the owner can create a market
    (asserts! (> end-block start-block) err-invalid-parameter) ;; Ensure end block is after start block
    (asserts! (> start-price u0) err-invalid-parameter) ;; Ensure start price is greater than 0
    (map-set markets market-id
      {
        start-price: start-price,
        end-price: u0,
        total-up-stake: u0,
        total-down-stake: u0,
        start-block: start-block,
        end-block: end-block,
        resolved: false
      }
    )
    (var-set market-counter (+ market-id u1)) ;; Increment the market counter
    (ok market-id) ;; Return the new market ID
  )
)

;; Make a prediction on a market
(define-public (make-prediction (market-id uint) (prediction (string-ascii 4)) (stake uint))
  (let
    (
      (market (unwrap! (map-get? markets market-id) err-not-found)) ;; Get the market details
      (current-block stacks-block-height) ;; Get the current block height
    )
    (asserts! (and (>= current-block (get start-block market)) (< current-block (get end-block market))) err-market-closed) ;; Ensure market is open
    (asserts! (or (is-eq prediction "up") (is-eq prediction "down")) err-invalid-prediction) ;; Ensure prediction is valid
    (asserts! (>= stake (var-get minimum-stake)) err-invalid-prediction) ;; Ensure stake is above minimum
    (asserts! (<= stake (stx-get-balance tx-sender)) err-insufficient-balance) ;; Ensure user has sufficient balance
    
    (try! (stx-transfer? stake tx-sender (as-contract tx-sender))) ;; Transfer stake to contract
    
    (map-set user-predictions {market-id: market-id, user: tx-sender}
      {prediction: prediction, stake: stake, claimed: false}
    )
    
    (map-set markets market-id
      (merge market
        {
          total-up-stake: (if (is-eq prediction "up")
                            (+ (get total-up-stake market) stake)
                            (get total-up-stake market)),
          total-down-stake: (if (is-eq prediction "down")
                              (+ (get total-down-stake market) stake)
                              (get total-down-stake market))
        }
      )
    )
    (ok true) ;; Return success
  )
)

;; Resolve a market
(define-public (resolve-market (market-id uint) (end-price uint))
  (let
    (
      (market (unwrap! (map-get? markets market-id) err-not-found)) ;; Get the market details
    )
    (asserts! (is-eq tx-sender (var-get oracle-address)) err-owner-only) ;; Ensure only the oracle can resolve
    (asserts! (>= stacks-block-height (get end-block market)) err-market-closed) ;; Ensure market has ended
    (asserts! (not (get resolved market)) err-market-closed) ;; Ensure market is not already resolved
    (asserts! (> end-price u0) err-invalid-parameter) ;; Ensure end price is valid
    
    (map-set markets market-id
      (merge market
        {
          end-price: end-price,
          resolved: true
        }
      )
    )
    (ok true) ;; Return success
  )
)

;; Claim winnings from a market
(define-public (claim-winnings (market-id uint))
  (let
    (
      (market (unwrap! (map-get? markets market-id) err-not-found)) ;; Get the market details
      (prediction (unwrap! (map-get? user-predictions {market-id: market-id, user: tx-sender}) err-not-found)) ;; Get the user's prediction
    )
    (asserts! (get resolved market) err-market-closed) ;; Ensure market is resolved
    (asserts! (not (get claimed prediction)) err-already-claimed) ;; Ensure winnings are not already claimed
    
    (let
      (
        (winning-prediction (if (> (get end-price market) (get start-price market)) "up" "down")) ;; Determine winning prediction
        (total-stake (+ (get total-up-stake market) (get total-down-stake market))) ;; Calculate total stake
        (winning-stake (if (is-eq winning-prediction "up") (get total-up-stake market) (get total-down-stake market))) ;; Calculate winning stake
      )
      (asserts! (is-eq (get prediction prediction) winning-prediction) err-invalid-prediction) ;; Ensure user's prediction is correct
      
      (let
        (
          (winnings (/ (* (get stake prediction) total-stake) winning-stake)) ;; Calculate winnings
          (fee (/ (* winnings (var-get fee-percentage)) u100)) ;; Calculate fee
          (payout (- winnings fee)) ;; Calculate payout
        )
        (try! (as-contract (stx-transfer? payout (as-contract tx-sender) tx-sender))) ;; Transfer payout to user
        (try! (as-contract (stx-transfer? fee (as-contract tx-sender) contract-owner))) ;; Transfer fee to contract owner
        
        (map-set user-predictions {market-id: market-id, user: tx-sender}
          (merge prediction {claimed: true})
        )
        (ok payout) ;; Return payout amount
      )
    )
  )
)

;; Getter functions

;; Get market details
(define-read-only (get-market (market-id uint))
  (map-get? markets market-id)
)

;; Get user prediction details
(define-read-only (get-user-prediction (market-id uint) (user principal))
  (map-get? user-predictions {market-id: market-id, user: user})
)

;; Get contract balance
(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender))
)

;; Admin functions

;; Set oracle address
(define-public (set-oracle-address (new-address principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only) ;; Ensure only the owner can set the oracle address
    (asserts! (is-eq new-address new-address) err-invalid-parameter) ;; Ensure new-address is not an empty principal
    (ok (var-set oracle-address new-address)) ;; Set the new oracle address
  )
)

;; Set minimum stake amount
(define-public (set-minimum-stake (new-minimum uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only) ;; Ensure only the owner can set the minimum stake
    (asserts! (> new-minimum u0) err-invalid-parameter) ;; Ensure new-minimum is greater than zero
    (ok (var-set minimum-stake new-minimum)) ;; Set the new minimum stake
  )
)

;; Set fee percentage
(define-public (set-fee-percentage (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only) ;; Ensure only the owner can set the fee percentage
    (asserts! (<= new-fee u100) err-invalid-parameter) ;; Ensure new-fee is between 0 and 100
    (ok (var-set fee-percentage new-fee)) ;; Set the new fee percentage
  )
)

;; Withdraw fees from the contract
(define-public (withdraw-fees (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only) ;; Ensure only the owner can withdraw fees
    (asserts! (<= amount (stx-get-balance (as-contract tx-sender))) err-insufficient-balance) ;; Ensure amount is available in contract balance
    (try! (as-contract (stx-transfer? amount (as-contract tx-sender) contract-owner))) ;; Transfer amount to contract owner
    (ok amount) ;; Return withdrawn amount
  )
)