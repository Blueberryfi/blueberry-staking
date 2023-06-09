### Concept
Token Distribution 2.0 aims to address common issues found in early token distributions, such as short-term liquidity and reward allocations that don't align with the long-term goals of the protocol. Blueberry introduces an innovative mechanism for a fair token distribution and launch: Bonded Blueberry ($bdBLB). Expanded below - 

**Bonded Blueberry ($bdBLB)**
Bonded Blueberry is the vesting rewards token, distributed every two weeks to those holding bTokens, the receipt token for lending on Blueberry markets.

Bonded Blueberry is the vesting governance token. 1 $bdBLB is redeemable for 1 $BLB over the course of 1 year. However, this vesting concept differs from traditional vesting, which unlocks tokens over time.
Instead, $bdBLB introduces an Acceleration Fee Vesting model based on the Early Unlock Peanlty Ratio.

**Early Unlock Penalty Ratio**
The Early Unlock Penalty Ratio represents the total penalty associated with unlocking tokens early in the vesting period.The penalty ratio is divided into two components: acceleration fee penalty and redistribution penalty both of them utilize the `basePenaltyRatioPercent` of 35% that get added together for a total of 70%. The ratio starts at 70% (acceleration fee penalty + redistribution penalty), leaving 30% vested at the beginning of the vesting period. The 70% initial penalty is the actual thing that vests linearly over time (e.g. at 6 months, the penalty ratio would be a total of 35%). 

As the vesting period progresses, the Early Unlock Penalty Ratio decreases linearly over the 1-year vesting period, without regard to the underlying $BLB price (starting at 70%). This means that the longer a user holds their $bdBLB tokens, the lower the penalty for accelerating the vesting process.

When a distribution occurs, the Initial Acceleration Fee is set automatically based on the price of the underlying $bdBLB at the time of distribution, referred to as the `priceUnderlying`. This Initial Acceleration Fee remains constant throughout the vesting period, regardless of the current $BLB price.

**Acceleration Fee Mechanics**
When a user chooses to accelerate the vesting process, a portion of their unlocked tokens will be redistributed among the other holders of that Epoch's batch of $bdBLB. The redistributed tokens are calculated based on the redistribution penalty, which is 50% of the Early Unlock Penalty Ratio at the time of acceleration.

**Redistribution**
50% of the Early Unlock Penalty Ratio is removed from the user’s received rewards and redistributed to other users in the bdBLB distribution epoch. This should be technically fairly simple as the tokens will just be left in the batch of bdBLB and become claimable pro rate by other users in the epoch batch. 

**Claiming Period**
$bdBLB is distributed and claimable each Monday of every two weeks, called an “Epoch.”

**Scenarios**
Let's consider a few scenarios of users performing accelerations at different points in the vesting period and with different Initial_BLB_Prices and Current_BLB_Prices:

1. Early Acceleration (Early Unlock Penalty Ratio at 60% ):
    1. Days into Vest - ~51 Days or 14.28% of the vest duration
    - Acceleration Fee Penalty: 30%
    - Redistribution Penalty: 30%
    - Initial BLB Price: $1
    - Current BLB Price: $1.2
    - Tokens Received: 70% of user's $bdBLB balance
    - Total Value Received: 70% * Current_BLB_Price * user's $bdBLB balance
    - Cost: 30% * Initial_BLB_Price * user's $bdBLB balance
2. Mid Acceleration (Early Unlock Penalty Ratio at 30%):
    - Acceleration Fee Penalty: 15%
    - Redistribution Penalty: 15%
    - Initial BLB Price: $1.5
    - Current BLB Price: $1.8
    - Tokens Received: 85% of user's $bdBLB balance
    - Total Value Received: 85% * Current_BLB_Price * user's $bdBLB balance
    - Cost: 15% * Initial_BLB_Price * user's $bdBLB balance
3. Late Acceleration (Early Unlock Penalty Ratio at 10%):
    - Acceleration Fee Penalty: 5%
    - Redistribution Penalty: 5%
    - Initial BLB Price: $2
    - Current BLB Price: $2.5
    - Tokens Received: 95% of user's $bdBLB balance
    - Total Value Received: 95% * Current_BLB_Price * user's $bdBLB balance
    - Cost: 5% * Initial_BLB_Price * user's $bdBLB balance
    
    These scenarios demonstrate how the tokens received, total value received, and cost vary depending on the user's acceleration timing, the Initial_BLB_Price, and the current $BLB price. The earlier a user decides to accelerate their vesting, the higher the penalties they will face, while the penalties decrease as the vesting period progresses.
    
    This model disincentivizes short-term liquidity providers, rewarding long-term believers in the protocol, and builds long-term liquidity for the benefit of the entire ecosystem, while still allowing users to exit. Fees are taken by the DAO treasury and used to buy back and make liquidity for the token.