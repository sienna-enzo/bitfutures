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