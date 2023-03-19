# UniAsset Smart Contracts

A suite of smart contracts for asset tokenization/fractionalization platform.

## Supported Function & Operation Logic

`Staking.sol`, `LP.sol`, `Ownable.sol`: Stake `ETH` in the platform to provide liquidity, in exchange for staking reward (partition of trading/management fee earned by the platform).

`IERC20.sol`, `LP.sol`, `Token.sol`: After the platform acquires underlying assets, fractionalized tokens will be minted for sale.

`LP.sol`: Process counter trading of fractionalized tokens and escrow of liquidity fund (`ETH`).

`Privileges.sol`: Authorization management for each function. Define 3 isolated level of security.

| Security Role |  Authorized Operations  | SK Management Requirement |
|:-----|:--------:|------:|
| `ParamAdmin`   | adjust fees, list/delist fractionalized assets, adjust reward rates, add/remove vault addresses | Held by authorized personnel, with at least `2-of-n` multisig |
| `FundAdmin`   |  transfer of fund to client, authorize purchase of underlying assets  | encrypted on highly-secured server with minimum access by human |
| `SuperAdmin`   | re-appointment of `ParamAdmin` and `FundAdmin` | held by authorized executive, cold storage, with at least `(n-2) of n` multisig  |