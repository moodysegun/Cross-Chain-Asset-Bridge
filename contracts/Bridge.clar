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
(define-constant ERR_PROPOSAL_NOT_FOUND (err u109))
(define-constant ERR_PROPOSAL_EXPIRED (err u110))
(define-constant ERR_PROPOSAL_NOT_EXECUTABLE (err u111))
(define-constant ERR_ALREADY_VOTED (err u112))
(define-constant ERR_INVALID_PROPOSAL_TYPE (err u113))
(define-constant ERR_INSUFFICIENT_STAKE (err u114))
(define-constant ERR_ACTIVITY_NOT_FOUND (err u115))

(define-data-var contract-paused bool false)
(define-data-var bridge-fee uint u1000000)
(define-data-var minimum-bridge-amount uint u5000000)
(define-data-var total-locked uint u0)
(define-data-var total-transactions uint u0)
(define-data-var governance-threshold uint u10000000)
(define-data-var voting-period uint u1008)
(define-data-var execution-delay uint u144)
(define-data-var proposal-counter uint u0)

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

(define-map governance-proposals uint {
    proposer: principal,
    proposal-type: uint,
    target-value: uint,
    target-chain: uint,
    target-validator: principal,
    start-height: uint,
    end-height: uint,
    execution-height: uint,
    yes-votes: uint,
    no-votes: uint,
    executed: bool,
    cancelled: bool
})

(define-map user-votes { proposal-id: uint, voter: principal } { vote: bool, power: uint })
(define-map governance-stakes principal uint)
(define-map user-transaction-count principal uint)
(define-map user-transactions { user: principal, tx-index: uint } { amount: uint, timestamp: uint, chain: uint })
(define-map validator-activity principal { processed: uint, last-active: uint })
(define-map daily-volume { date: uint } { total: uint, count: uint })
(define-map top-transactions uint { user: principal, amount: uint, timestamp: uint })
(define-data-var transaction-counter uint u0)
(define-data-var top-tx-counter uint u0)

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
        
        (let (
            (user-count (default-to u0 (map-get? user-transaction-count sender)))
            (tx-index user-count)
            (current-day (/ stacks-block-height u144))
            (daily-data (default-to { total: u0, count: u0 } (map-get? daily-volume { date: current-day })))
            (tx-counter (var-get transaction-counter))
        )
            (map-set user-transaction-count sender (+ user-count u1))
            (map-set user-transactions { user: sender, tx-index: tx-index } { amount: amount, timestamp: stacks-block-height, chain: destination-chain })
            (map-set daily-volume { date: current-day } { total: (+ (get total daily-data) amount), count: (+ (get count daily-data) u1) })
            (if (> amount u100000)
                (begin
                    (map-set top-transactions tx-counter { user: sender, amount: amount, timestamp: stacks-block-height })
                    (var-set top-tx-counter (+ tx-counter u1))
                )
                true
            )
            (var-set transaction-counter (+ tx-counter u1))
        )
        
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
        
        (let (
            (validator-stats (default-to { processed: u0, last-active: u0 } (map-get? validator-activity tx-sender)))
        )
            (map-set validator-activity tx-sender { processed: (+ (get processed validator-stats) u1), last-active: stacks-block-height })
        )
        
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

(define-public (stake-for-governance (amount uint))
    (let (
        (current-stake (get-governance-stake tx-sender))
    )
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (>= (stx-get-balance tx-sender) amount) ERR_INSUFFICIENT_BALANCE)
        
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (map-set governance-stakes tx-sender (+ current-stake amount))
        
        (print { event: "governance-staked", user: tx-sender, amount: amount })
        (ok amount)
    )
)

(define-public (unstake-governance (amount uint))
    (let (
        (current-stake (get-governance-stake tx-sender))
    )
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (>= current-stake amount) ERR_INSUFFICIENT_BALANCE)
        
        (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
        (map-set governance-stakes tx-sender (- current-stake amount))
        
        (print { event: "governance-unstaked", user: tx-sender, amount: amount })
        (ok amount)
    )
)

(define-public (create-proposal (proposal-type uint) (target-value uint) (target-chain uint) (target-validator principal))
    (let (
        (proposer-stake (get-governance-stake tx-sender))
        (proposal-id (+ (var-get proposal-counter) u1))
        (start-height stacks-block-height)
        (end-height (+ start-height (var-get voting-period)))
        (execution-height (+ end-height (var-get execution-delay)))
    )
        (asserts! (>= proposer-stake (var-get governance-threshold)) ERR_INSUFFICIENT_STAKE)
        (asserts! (<= proposal-type u7) ERR_INVALID_PROPOSAL_TYPE)
        
        (var-set proposal-counter proposal-id)
        (map-set governance-proposals proposal-id {
            proposer: tx-sender,
            proposal-type: proposal-type,
            target-value: target-value,
            target-chain: target-chain,
            target-validator: target-validator,
            start-height: start-height,
            end-height: end-height,
            execution-height: execution-height,
            yes-votes: u0,
            no-votes: u0,
            executed: false,
            cancelled: false
        })
        
        (print {
            event: "proposal-created",
            proposal-id: proposal-id,
            proposer: tx-sender,
            proposal-type: proposal-type,
            target-value: target-value
        })
        
        (ok proposal-id)
    )
)

(define-public (vote-on-proposal (proposal-id uint) (vote bool))
    (let (
        (proposal-data (unwrap! (map-get? governance-proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
        (voter-stake (get-governance-stake tx-sender))
        (current-height stacks-block-height)
        (vote-key { proposal-id: proposal-id, voter: tx-sender })
    )
        (asserts! (> voter-stake u0) ERR_INSUFFICIENT_STAKE)
        (asserts! (>= current-height (get start-height proposal-data)) ERR_EXPIRED)
        (asserts! (<= current-height (get end-height proposal-data)) ERR_PROPOSAL_EXPIRED)
        (asserts! (is-none (map-get? user-votes vote-key)) ERR_ALREADY_VOTED)
        (asserts! (not (get cancelled proposal-data)) ERR_PROPOSAL_EXPIRED)
        
        (map-set user-votes vote-key { vote: vote, power: voter-stake })
        
        (if vote
            (map-set governance-proposals proposal-id 
                (merge proposal-data { yes-votes: (+ (get yes-votes proposal-data) voter-stake) }))
            (map-set governance-proposals proposal-id 
                (merge proposal-data { no-votes: (+ (get no-votes proposal-data) voter-stake) }))
        )
        
        (print {
            event: "vote-cast",
            proposal-id: proposal-id,
            voter: tx-sender,
            vote: vote,
            power: voter-stake
        })
        
        (ok true)
    )
)

(define-public (execute-proposal (proposal-id uint))
    (let (
        (proposal-data (unwrap! (map-get? governance-proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
        (current-height stacks-block-height)
        (total-votes (+ (get yes-votes proposal-data) (get no-votes proposal-data)))
        (proposal-type (get proposal-type proposal-data))
        (target-value (get target-value proposal-data))
        (target-chain (get target-chain proposal-data))
        (target-validator (get target-validator proposal-data))
    )
        (asserts! (not (get executed proposal-data)) ERR_ALREADY_PROCESSED)
        (asserts! (not (get cancelled proposal-data)) ERR_PROPOSAL_EXPIRED)
        (asserts! (>= current-height (get execution-height proposal-data)) ERR_EXPIRED)
        (asserts! (> (get yes-votes proposal-data) (get no-votes proposal-data)) ERR_PROPOSAL_NOT_EXECUTABLE)
        (asserts! (> total-votes u0) ERR_PROPOSAL_NOT_EXECUTABLE)
        
        (map-set governance-proposals proposal-id (merge proposal-data { executed: true }))
        
        (if (is-eq proposal-type u1)
            (begin (var-set bridge-fee target-value) (print { event: "fee-updated-by-governance", new-fee: target-value }) true)
            (if (is-eq proposal-type u2)
                (begin (var-set minimum-bridge-amount target-value) (print { event: "minimum-updated-by-governance", new-minimum: target-value }) true)
                (if (is-eq proposal-type u3)
                    (begin (var-set contract-paused true) (print { event: "contract-paused-by-governance" }) true)
                    (if (is-eq proposal-type u4)
                        (begin (var-set contract-paused false) (print { event: "contract-unpaused-by-governance" }) true)
                        (if (is-eq proposal-type u5)
                            (begin 
                                (map-set supported-chains target-chain true)
                                (map-set chain-validators target-chain target-validator)
                                (print { event: "chain-added-by-governance", chain-id: target-chain, validator: target-validator })
                                true)
                            (if (is-eq proposal-type u6)
                                (begin
                                    (map-delete supported-chains target-chain)
                                    (map-delete chain-validators target-chain)
                                    (print { event: "chain-removed-by-governance", chain-id: target-chain })
                                    true)
                                (if (is-eq proposal-type u7)
                                    (begin (var-set governance-threshold target-value) (print { event: "governance-threshold-updated", new-threshold: target-value }) true)
                                    false
                                )
                            )
                        )
                    )
                )
            )
        )
        
        (print {
            event: "proposal-executed",
            proposal-id: proposal-id,
            proposal-type: proposal-type,
            executor: tx-sender
        })
        
        (ok proposal-id)
    )
)

(define-public (cancel-proposal (proposal-id uint))
    (let (
        (proposal-data (unwrap! (map-get? governance-proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
        (current-height stacks-block-height)
    )
        (asserts! (or (is-eq tx-sender (get proposer proposal-data)) (is-eq tx-sender CONTRACT_OWNER)) ERR_UNAUTHORIZED)
        (asserts! (not (get executed proposal-data)) ERR_ALREADY_PROCESSED)
        (asserts! (not (get cancelled proposal-data)) ERR_ALREADY_PROCESSED)
        (asserts! (<= current-height (get end-height proposal-data)) ERR_PROPOSAL_EXPIRED)
        
        (map-set governance-proposals proposal-id (merge proposal-data { cancelled: true }))
        
        (print {
            event: "proposal-cancelled",
            proposal-id: proposal-id,
            canceller: tx-sender
        })
        
        (ok proposal-id)
    )
)

(define-read-only (get-governance-stake (user principal))
    (default-to u0 (map-get? governance-stakes user))
)

(define-read-only (get-proposal-info (proposal-id uint))
    (map-get? governance-proposals proposal-id)
)

(define-read-only (get-user-vote (proposal-id uint) (voter principal))
    (map-get? user-votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (get-governance-settings)
    {
        threshold: (var-get governance-threshold),
        voting-period: (var-get voting-period),
        execution-delay: (var-get execution-delay),
        total-proposals: (var-get proposal-counter)
    }
)

(define-read-only (is-proposal-executable (proposal-id uint))
    (match (map-get? governance-proposals proposal-id)
        proposal-data (let (
            (current-height stacks-block-height)
            (total-votes (+ (get yes-votes proposal-data) (get no-votes proposal-data)))
        )
            (and
                (not (get executed proposal-data))
                (not (get cancelled proposal-data))
                (>= current-height (get execution-height proposal-data))
                (> (get yes-votes proposal-data) (get no-votes proposal-data))
                (> total-votes u0)
            )
        )
        false
    )
)

(define-read-only (get-user-transaction-count (user principal))
    (ok (default-to u0 (map-get? user-transaction-count user)))
)

(define-read-only (get-user-transaction (user principal) (index uint))
    (ok (map-get? user-transactions { user: user, tx-index: index }))
)

(define-read-only (get-user-recent-activity (user principal))
    (let (
        (count (default-to u0 (map-get? user-transaction-count user)))
    )
        (ok {
            total-transactions: count,
            last-tx-index: (if (> count u0) (- count u1) u0)
        })
    )
)

(define-read-only (get-daily-volume (date uint))
    (ok (map-get? daily-volume { date: date }))
)

(define-read-only (get-current-day-volume)
    (let (
        (current-day (/ stacks-block-height u144))
    )
        (ok (map-get? daily-volume { date: current-day }))
    )
)

(define-read-only (get-average-transaction-size (date uint))
    (let (
        (daily-data (map-get? daily-volume { date: date }))
    )
        (match daily-data
            data (if (> (get count data) u0)
                (ok (/ (get total data) (get count data)))
                (ok u0)
            )
            (ok u0)
        )
    )
)

(define-read-only (get-total-transactions)
    (ok (var-get transaction-counter))
)

(define-read-only (get-validator-activity (validator principal))
    (ok (map-get? validator-activity validator))
)

(define-read-only (get-top-transaction (index uint))
    (ok (map-get? top-transactions index))
)

(define-read-only (get-transaction-statistics)
    (ok {
        total-transactions: (var-get transaction-counter),
        top-transactions-count: (var-get top-tx-counter)
    })
)
