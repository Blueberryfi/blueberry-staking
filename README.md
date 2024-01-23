## BlueberryStaking Smart Contract
This is the README file for the BlueberryStaking smart contract, which implements a staking mechanism with vesting for bdBLB token distribution. The contract allows users to stake specific tokens and earn rewards in the form of BLB tokens. It also provides vesting functionality for the distributed rewards.

### Contract Details
- Contract Name: BlueberryStaking
- License: MIT
- Solidity Version: 0.8.19
- Author: BlueberryProtocol

- Description
BlueberryStaking is a smart contract that facilitates the staking of tokens and the distribution of rewards in the form of BLB tokens. The contract supports multiple tokens that can be staked, and it includes vesting functionality for the distributed rewards. Users can stake tokens, earn rewards, unstake tokens, claim rewards, accelerate vesting, and complete vesting based on the rules defined in the contract.

The contract is implemented using OpenZeppelin library contracts, including ERC20, Pausable, and Ownable.

### Features
The BlueberryStaking contract includes the following features:

- Staking: Users can stake tokens by calling the stake function and providing the tokens and amounts they want to stake. The staked tokens are transferred to the contract.

- Unstaking: Users can unstake tokens by calling the unstake function and providing the tokens and amounts they want to unstake. The unstaked tokens are transferred back to the user.

- Rewards: Users can earn rewards by staking tokens. The rewards are calculated based on the staked tokens and the reward rate. Users can claim their rewards by calling the startVesting function.

- Vesting: The contract includes vesting functionality for the distributed rewards. Users can complete vesting for specific vesting schedules by calling the `completeVesting` function. They can also accelerate vesting by paying an acceleration fee using the `accelerateVesting` function.

- Management: The contract includes various management functions that can be called only by the contract owner. These functions allow the owner to change the reward rate, reward duration, vest length, add or remove supported tokens, change the BLB token address, pause or unpause the contract, and notify reward amounts.
