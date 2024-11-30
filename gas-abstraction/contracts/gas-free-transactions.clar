;; Gas Station Network Contract
;; Allows users to send transactions without holding STX for gas fees

(define-constant ERROR-UNAUTHORIZED (err u100))
(define-constant ERROR-INVALID-RELAY-ADDRESS (err u101))
(define-constant ERROR-INSUFFICIENT-USER-BALANCE (err u102))
(define-constant ERROR-INVALID-TRANSACTION-SIGNATURE (err u103))

;; Data variables
(define-data-var contract-administrator principal tx-sender)
(define-map authorized-relay-addresses principal bool)
(define-map user-account-balances principal uint)
(define-map user-transaction-nonces principal uint)

;; Read-only functions
(define-read-only (get-contract-administrator)
    (var-get contract-administrator)
)

(define-read-only (is-relay-address-authorized (relay-address principal))
    (default-to false (map-get? authorized-relay-addresses relay-address))
)

(define-read-only (get-user-account-balance (user-address principal))
    (default-to u0 (map-get? user-account-balances user-address))
)

(define-read-only (get-user-transaction-nonce (user-address principal))
    (default-to u0 (map-get? user-transaction-nonces user-address))
)

;; Authentication helper
(define-private (is-contract-administrator)
    (is-eq tx-sender (var-get contract-administrator))
)

;; Administrator management functions
(define-public (transfer-contract-ownership (new-administrator-address principal))
    (begin
        (asserts! (is-contract-administrator) ERROR-UNAUTHORIZED)
        (ok (var-set contract-administrator new-administrator-address))
    )
)

;; Relay management
(define-public (add-authorized-relay (relay-address principal))
    (begin
        (asserts! (is-contract-administrator) ERROR-UNAUTHORIZED)
        (ok (map-set authorized-relay-addresses relay-address true))
    )
)

(define-public (remove-authorized-relay (relay-address principal))
    (begin
        (asserts! (is-contract-administrator) ERROR-UNAUTHORIZED)
        (ok (map-set authorized-relay-addresses relay-address false))
    )
)

;; Deposit management
(define-public (deposit-funds)
    (let ((deposit-amount (stx-get-balance tx-sender)))
        (begin
            (try! (stx-transfer? deposit-amount tx-sender (as-contract tx-sender)))
            (map-set user-account-balances tx-sender 
                (+ (get-user-account-balance tx-sender) deposit-amount))
            (ok deposit-amount)
        )
    )
)

(define-public (withdraw-funds (withdrawal-amount uint))
    (let ((current-user-balance (get-user-account-balance tx-sender)))
        (begin
            (asserts! (<= withdrawal-amount current-user-balance) ERROR-INSUFFICIENT-USER-BALANCE)
            (try! (as-contract (stx-transfer? withdrawal-amount (as-contract tx-sender) tx-sender)))
            (map-set user-account-balances tx-sender 
                (- current-user-balance withdrawal-amount))
            (ok withdrawal-amount)
        )
    )
)

;; Relay transaction handling
(define-public (process-relayed-transaction
    (user-address principal)
    (destination-contract principal)
    (target-function-name (string-ascii 128))
    (function-arguments (list 10 (string-ascii 128)))
    (transaction-gas-price uint)
    (transaction-gas-limit uint)
    (transaction-signature (buff 65))
)
    (let (
        (current-nonce (get-user-transaction-nonce user-address))
        (relay-address tx-sender)
        (transaction-hash (hash160 (concat (concat (concat 
            (principal-to-buff user-address)
            (principal-to-buff destination-contract))
            (string-to-buff target-function-name))
            (uint-to-buff current-nonce))))
    )
        (begin
            ;; Verify relay is authorized
            (asserts! (is-relay-address-authorized relay-address) ERROR-INVALID-RELAY-ADDRESS)
            
            ;; Verify signature
            (asserts! (is-eq (verify-signature transaction-hash transaction-signature user-address) true) 
                ERROR-INVALID-TRANSACTION-SIGNATURE)
            
            ;; Verify user has enough balance
            (asserts! (>= (get-user-account-balance user-address) 
                (* transaction-gas-price transaction-gas-limit)) ERROR-INSUFFICIENT-USER-BALANCE)
            
            ;; Update nonce
            (map-set user-transaction-nonces user-address (+ current-nonce u1))
            
            ;; Execute the transaction
            (contract-call? destination-contract target-function-name function-arguments)
            
            ;; Deduct gas fees
            (map-set user-account-balances user-address 
                (- (get-user-account-balance user-address) 
                   (* transaction-gas-price transaction-gas-limit)))
            
            ;; Pay relay
            (try! (as-contract (stx-transfer? 
                (* transaction-gas-price transaction-gas-limit) 
                (as-contract tx-sender) 
                relay-address)))
            
            (ok true)
        )
    )
)

;; Emergency functions
(define-public (emergency-fund-recovery)
    (begin
        (asserts! (is-contract-administrator) ERROR-UNAUTHORIZED)
        (let ((contract-balance (stx-get-balance (as-contract tx-sender))))
            (try! (as-contract (stx-transfer? 
                contract-balance 
                (as-contract tx-sender) 
                (var-get contract-administrator))))
            (ok contract-balance)
        )
    )
)