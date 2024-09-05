# Proveably Random Raffle Contracts

## About

This code is to create a proveably random smart contract lottery.

## What do we want it to do?

1. Until a pre-determined time, have users enter the raffle by paying for a ticket
   1. The ticket fees are going to go to the winner during the draw
2. When time's up, select a random winner among all users who entered the raffle - based on a random number generated.
3. Using "ChainLink aka CL" VRF & CL Automation
   1. CL VRF -> Randomness
   2. CL Automation -> Time Based Trigger
4. Pay the winner all the currency present in the contract.