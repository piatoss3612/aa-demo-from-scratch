# AA from Scratch

This repository is for the basic understanding of `Account Abstraction in Ethereum`.

## What is Account Abstraction?

In Ethereum, there are two types of accounts: Externally Owned Accounts (EOAs) and Contract Accounts. EOAs are controlled by private keys and can send transactions, while Contract Accounts are controlled by code and can execute transactions. In the current Ethereum network, only EOAs can initiate transactions, which is a huge barrier to user experience:

- Users need private keys or wallets to interact with the network, which requires users to manage their private keys and wallets custodianship.
- Users need to pay for gas fees, though they may not have any Ether in their wallets.
- If users lose their private keys, they lose access to their assets forever.
- Users want to customize their security policies, but they have to follow the built-in security policies of Ethereum (e.g., ECDSA signature).

Account Abstraction is a concept that allows Contract Accounts to initiate transactions, which can solve the above problems. In other words, Account Abstraction allows users to interact with the network without knowing their private keys, what the hell is transactions, and how to pay for gas fees. This is a huge step towards user experience and privacy.

One of the mature implementations of Account Abstraction is EIP-4337 (https://eips.ethereum.org/EIPS/eip-4337) which does not require protocol changes. There are also built-in implementations in some blockchains, such as zkSync and NEAR Protocol.
