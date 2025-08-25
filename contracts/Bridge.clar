;; title: Bridge

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_AMOUNT (err u101))
(define-constant ERR_INSUFFICIENT_BALANCE (err u102))
(define-constant ERR_ALREADY_PROCESSED (err u103))
(define-constant ERR_INVALID_CHAIN (err u104))
(define-constant ERR_PAUSED (err u105))
(define-constant ERR_INVALID_SIGNATURE (err u106))
(define-constant ERR_EXPIRED (err u107))
(define-constant ERR_MINIMUM_AMOUNT (err u108))

(define-data-var contract-paused bool false)
(define-data-var bridge-fee uint u1000000)
(define-data-var minimum-bridge-amount uint u5000000)
(define-data-var total-locked uint u0)
(define-data-var total-transactions uint u0)

(define-map locked-balances principal uint)
(define-map processed-transactions (buff 32) bool)
(define-map supported-chains uint bool)
(define-map chain-validators uint principal)
(define-map pending-withdrawals (buff 32) {
    recipient: principal,
    amount: uint,
    source-chain-id: uint,
    expiry: uint,
    processed: bool
})

(define-map user-nonces principal uint)

(define-public (initialize)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set supported-chains u1 true)
        (map-set supported-chains u2 true)
        (map-set chain-validators u1 CONTRACT_OWNER)
        (map-set chain-validators u2 CONTRACT_OWNER)
        (ok true)
    )
)

(define-public (lock-assets (amount uint) (destination-chain uint) (recipient (buff 64)))
    (let (
        (sender tx-sender)
        (fee (var-get bridge-fee))
        (total-amount (+ amount fee))
        (current-balance (stx-get-balance sender))
        (tx-id (get-tx-id sender amount destination-chain))
    )
        (asserts! (not (var-get contract-paused)) ERR_PAUSED)
        (asserts! (>= amount (var-get minimum-bridge-amount)) ERR_MINIMUM_AMOUNT)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (>= current-balance total-amount) ERR_INSUFFICIENT_BALANCE)
        (asserts! (default-to true (map-get? supported-chains destination-chain)) ERR_INVALID_CHAIN)
        (asserts! (is-none (map-get? processed-transactions tx-id)) ERR_ALREADY_PROCESSED)
        
        (try! (stx-transfer? total-amount sender (as-contract tx-sender)))
        
        (map-set locked-balances sender (+ (default-to u0 (map-get? locked-balances sender)) amount))
        (map-set processed-transactions tx-id true)
        (var-set total-locked (+ (var-get total-locked) amount))
        (var-set total-transactions (+ (var-get total-transactions) u1))
        
        (print {
            event: "asset-locked",
            sender: sender,
            amount: amount,
            destination-chain: destination-chain,
            recipient: recipient,
            tx-id: tx-id,
            fee: fee,
            block-height: stacks-block-height
        })
        
        (ok tx-id)
    )
)

(define-public (initiate-unlock (tx-id (buff 32)) (recipient principal) (amount uint) (source-chain-id uint))
    (let (
        (validator (unwrap! (map-get? chain-validators source-chain-id) ERR_INVALID_CHAIN))
        (expiry (+ stacks-block-height u144))
    )
        (asserts! (not (var-get contract-paused)) ERR_PAUSED)
        (asserts! (is-eq tx-sender validator) ERR_UNAUTHORIZED)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (is-none (map-get? pending-withdrawals tx-id)) ERR_ALREADY_PROCESSED)
        
        (map-set pending-withdrawals tx-id {
            recipient: recipient,
            amount: amount,
            source-chain-id: source-chain-id,
            expiry: expiry,
            processed: false
        })
        
        (print {
            event: "unlock-initiated",
            tx-id: tx-id,
            recipient: recipient,
            amount: amount,
            source-chain-id: source-chain-id,
            expiry: expiry
        })
        
        (ok tx-id)
    )
)

(define-public (complete-unlock (tx-id (buff 32)))
    (let (
        (withdrawal-data (unwrap! (map-get? pending-withdrawals tx-id) ERR_INVALID_AMOUNT))
        (recipient (get recipient withdrawal-data))
        (amount (get amount withdrawal-data))
        (expiry (get expiry withdrawal-data))
        (processed (get processed withdrawal-data))
    )
        (asserts! (not (var-get contract-paused)) ERR_PAUSED)
        (asserts! (not processed) ERR_ALREADY_PROCESSED)
        (asserts! (<= stacks-block-height expiry) ERR_EXPIRED)
        (asserts! (>= (stx-get-balance (as-contract tx-sender)) amount) ERR_INSUFFICIENT_BALANCE)
        
        (try! (as-contract (stx-transfer? amount tx-sender recipient)))
        
        (map-set pending-withdrawals tx-id (merge withdrawal-data { processed: true }))
        (map-set locked-balances recipient (+ (default-to u0 (map-get? locked-balances recipient)) amount))
        (var-set total-locked (- (var-get total-locked) amount))
        
        (print {
            event: "asset-unlocked",
            tx-id: tx-id,
            recipient: recipient,
            amount: amount,
            block-height: stacks-block-height
        })
        
        (ok amount)
    )
)

(define-public (emergency-withdraw (tx-id (buff 32)))
    (let (
        (withdrawal-data (unwrap! (map-get? pending-withdrawals tx-id) ERR_INVALID_AMOUNT))
        (recipient (get recipient withdrawal-data))
        (amount (get amount withdrawal-data))
        (expiry (get expiry withdrawal-data))
        (processed (get processed withdrawal-data))
    )
        (asserts! (is-eq tx-sender recipient) ERR_UNAUTHORIZED)
        (asserts! (not processed) ERR_ALREADY_PROCESSED)
        (asserts! (> stacks-block-height expiry) ERR_EXPIRED)
        
        (map-set pending-withdrawals tx-id (merge withdrawal-data { processed: true }))
        
        (print {
            event: "emergency-withdrawal",
            tx-id: tx-id,
            recipient: recipient,
            amount: amount
        })
        
        (ok amount)
    )
)

(define-public (set-bridge-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set bridge-fee new-fee)
        (print { event: "fee-updated", new-fee: new-fee })
        (ok new-fee)
    )
)

(define-public (set-minimum-amount (new-minimum uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set minimum-bridge-amount new-minimum)
        (print { event: "minimum-updated", new-minimum: new-minimum })
        (ok new-minimum)
    )
)

(define-public (pause-contract)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set contract-paused true)
        (print { event: "contract-paused" })
        (ok true)
    )
)

(define-public (unpause-contract)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set contract-paused false)
        (print { event: "contract-unpaused" })
        (ok true)
    )
)

(define-public (add-supported-chain (target-chain-id uint) (validator principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set supported-chains target-chain-id true)
        (map-set chain-validators target-chain-id validator)
        (print { event: "chain-added", chain-id: target-chain-id, validator: validator })
        (ok target-chain-id)
    )
)

(define-public (remove-supported-chain (target-chain-id uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-delete supported-chains target-chain-id)
        (map-delete chain-validators target-chain-id)
        (print { event: "chain-removed", chain-id: target-chain-id })
        (ok target-chain-id)
    )
)

(define-public (withdraw-fees (amount uint) (recipient principal))
    (let (
        (contract-balance (stx-get-balance (as-contract tx-sender)))
        (available-fees (- contract-balance (var-get total-locked)))
    )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (>= available-fees amount) ERR_INSUFFICIENT_BALANCE)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        
        (try! (as-contract (stx-transfer? amount tx-sender recipient)))
        
        (print { event: "fees-withdrawn", amount: amount, recipient: recipient })
        (ok amount)
    )
)

(define-read-only (get-bridge-info)
    {
        paused: (var-get contract-paused),
        fee: (var-get bridge-fee),
        minimum-amount: (var-get minimum-bridge-amount),
        total-locked: (var-get total-locked),
        total-transactions: (var-get total-transactions),
        contract-balance: (stx-get-balance (as-contract tx-sender))
    }
)

(define-read-only (get-locked-balance (user principal))
    (default-to u0 (map-get? locked-balances user))
)

(define-read-only (get-withdrawal-info (tx-id (buff 32)))
    (map-get? pending-withdrawals tx-id)
)

(define-read-only (is-chain-supported (target-chain-id uint))
    (default-to false (map-get? supported-chains target-chain-id))
)

(define-read-only (get-chain-validator (target-chain-id uint))
    (map-get? chain-validators target-chain-id)
)

(define-read-only (get-user-nonce (user principal))
    (default-to u0 (map-get? user-nonces user))
)

(define-read-only (is-transaction-processed (tx-id (buff 32)))
    (default-to false (map-get? processed-transactions tx-id))
)

(define-private (get-tx-id (sender principal) (amount uint) (destination-chain uint))
    (let (
        (nonce (+ (get-user-nonce sender) u1))
        (block-hash (unwrap-panic (get-stacks-block-info? id-header-hash (- stacks-block-height u1))))
    )
        (map-set user-nonces sender nonce)
        (sha256 (concat 
            (concat (unwrap-panic (to-consensus-buff? sender)) (unwrap-panic (to-consensus-buff? amount)))
            (concat (unwrap-panic (to-consensus-buff? destination-chain)) 
                (concat (unwrap-panic (to-consensus-buff? nonce)) block-hash))
        ))
    )
)

(define-private (increment-nonce (user principal))
    (let (
        (current-nonce (get-user-nonce user))
    )
        (map-set user-nonces user (+ current-nonce u1))
        (+ current-nonce u1)
    )
)

(define-read-only (get-available-fees)
    (let (
        (contract-balance (stx-get-balance (as-contract tx-sender)))
        (locked-amount (var-get total-locked))
    )
        (if (>= contract-balance locked-amount)
            (- contract-balance locked-amount)
            u0
        )
    )
)

(define-read-only (calculate-bridge-cost (amount uint))
    (+ amount (var-get bridge-fee))
)

(define-read-only (estimate-withdrawal-time (target-chain-id uint))
    (if (is-chain-supported target-chain-id)
        (ok u144)
        ERR_INVALID_CHAIN
    )
)
