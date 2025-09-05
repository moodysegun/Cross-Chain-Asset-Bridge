# 🌉 Cross-Chain Asset Bridge

A decentralized bridge enabling seamless and secure transfer of assets between different blockchains.

## 🚀 Features

- ✅ **Secure Asset Locking**: Lock STX tokens for cross-chain transfers
- 🔄 **Cross-Chain Validation**: Validator-based transaction verification
- 💰 **Fee Management**: Configurable bridge fees and minimum amounts
- ⚡ **Fast Withdrawals**: Quick asset unlocking with expiry protection
- 🛡️ **Emergency Controls**: Circuit breaker and emergency withdrawal functions
- 📊 **Transaction Tracking**: Complete audit trail of all bridge operations

## 📋 Contract Functions

### 🔒 Lock Assets
```clarity
(contract-call? .Bridge lock-assets amount destination-chain recipient)
```
Lock STX tokens for transfer to another chain.

### 🔓 Unlock Assets
```clarity
(contract-call? .Bridge initiate-unlock tx-id recipient amount chain-id)
(contract-call? .Bridge complete-unlock tx-id)
```
Two-step process for unlocking assets on the destination chain.

### ⚙️ Admin Functions
```clarity
(contract-call? .Bridge set-bridge-fee new-fee)
(contract-call? .Bridge set-minimum-amount new-minimum)
(contract-call? .Bridge pause-contract)
(contract-call? .Bridge unpause-contract)
```

### 📈 Read Functions
```clarity
(contract-call? .Bridge get-bridge-info)
(contract-call? .Bridge get-locked-balance user)
(contract-call? .Bridge get-withdrawal-info tx-id)
```

## 🛠️ Setup

1. **Initialize Contract**: Run `initialize` function after deployment
2. **Configure Chains**: Add supported chains using `add-supported-chain`
3. **Set Parameters**: Configure fees and minimum amounts
4. **Deploy Validators**: Set up validator nodes for each supported chain

## 💡 Usage Example

```clarity
;; Lock 10 STX for transfer to chain 2
(contract-call? .Bridge lock-assets u10000000 u2 0x1234...)

;; Check bridge status
(contract-call? .Bridge get-bridge-info)

;; Complete withdrawal (validator only)
(contract-call? .Bridge complete-unlock tx-id)
```

## 🔐 Security

- **Multi-signature validation** for cross-chain transactions
- **Time-locked withdrawals** with expiry protection
- **Emergency pause** functionality for critical situations
- **Validator-based** transaction verification

## 📊 Bridge Economics

- **Bridge Fee**: Configurable fee per transaction (default: 1 STX)
- **Minimum Amount**: Minimum bridge amount (default: 5 STX)
- **Withdrawal Time**: ~144 blocks (~24 hours) maximum withdrawal window

## 🏗️ Architecture

The bridge operates using a lock-and-mint mechanism:

1. **Source Chain**: Assets are locked in the bridge contract
2. **Validation**: Cross-chain validators verify the lock transaction
3. **Destination Chain**: Equivalent assets are unlocked/minted
4. **Finalization**: Transaction is marked as completed

## 🧪 Testing

```bash
clarinet check
clarinet test
```

## 📝 Contract Info

- **Network**: Stacks Blockchain
- **Language**: Clarity
- **Security**: Audited and tested
- **Gas Optimization**: Efficient function design

---

Built with ❤️ for the multi-chain future 🚀
