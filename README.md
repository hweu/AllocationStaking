# Sample Hardhat Project

This project demonstrates a basic Hardhat use case. It comes with a sample contract, a test for that contract, and a Hardhat Ignition module that deploys that contract.

Try running some of the following tasks:

```shell
npx hardhat help
npx hardhat test
REPORT_GAS=true npx hardhat test
npx hardhat node
npx hardhat ignition deploy ./ignition/modules/Lock.js
```
技术依赖：OpenZeppelin
  OpenZeppelin库提供了一些安全的合约实现，如ERC20、SafeMath等。
该项目是一个基于以太坊的智能合约，主要用于管理和分发基于用户质押的流动性证明(LP)代币的ERC20奖励。该合约允许用户存入LP代币，并根据质押的数量和时间来计算和分发ERC20类型的奖励。
包含用户信息（UserInfo）、池子信息结构（PoolInfo）、销售(sale)、销售工厂(SalesFactory)、admin和Token
