// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig, CodeConstants} from "script/HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";


contract CreateSubscription is Script {

    function createSubscriptionUsingConfig() public returns ( uint256, address) {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        address account = helperConfig.getConfig().account;
        
        (uint256 subscriptionId, ) = createSubscription(vrfCoordinator, account);

        return (subscriptionId, vrfCoordinator);
    }

    function createSubscription(address vrfCoordinator, address account) public returns ( uint256, address) {
        console.log("Creating subscription on chain Id: ", block.chainid);
        
        vm.startBroadcast(account);
        uint256 subscriptionId = VRFCoordinatorV2_5Mock(vrfCoordinator).createSubscription();
        vm.stopBroadcast();

        console.log("Your subscription Id is: ", subscriptionId);
        return (subscriptionId, vrfCoordinator);

    }

    function run() public {
        createSubscriptionUsingConfig();

    }

}

contract FundSubscription is Script, CodeConstants {

    uint256 public constant FUND_AMOUNT = 3 ether; // i.e. 3 LINK (3 ether is a shortcut for 3e18)

    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        uint256 subscriptionId = helperConfig.getConfig().subscriptionId;
        address linkToken = helperConfig.getConfig().link;
        address account = helperConfig.getConfig().account;
        fundSubscription(vrfCoordinator, subscriptionId, linkToken, account);

    }

    function fundSubscription(address vrfCoordinator, uint256 subscriptionId, address linkToken, address account) public {
        console.log("Funding subscription: ", subscriptionId);
        console.log("Using coordinator: ", vrfCoordinator);
        console.log("On ChainId: ", block.chainid);

        if (block.chainid == LOCAL_CHAIN_ID) {
            vm.startBroadcast();
            VRFCoordinatorV2_5Mock(vrfCoordinator).fundSubscription(subscriptionId, FUND_AMOUNT * 100);
            vm.stopBroadcast();
        } else {
            vm.startBroadcast(account);
            LinkToken(linkToken).transferAndCall(vrfCoordinator, FUND_AMOUNT, abi.encode(subscriptionId));
            vm.stopBroadcast();
        }


    }

    function run() public {
        fundSubscriptionUsingConfig();
    }

}

contract AddConsumer is Script {

    function addConsumerUsingConfig(address mostRecentDeployed) public {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        uint256 subscriptionId = helperConfig.getConfig().subscriptionId;
        address account = helperConfig.getConfig().account;
        addConsumer(mostRecentDeployed, vrfCoordinator, subscriptionId, account);
    }

    function addConsumer(address contractToAddToVrf, address vrfCoordinator, uint256 subscriptionId, address account) public  {
        console.log("Adding consumer: ", contractToAddToVrf);
        console.log("Using coordinator: ", vrfCoordinator);
        console.log("On ChainId: ", block.chainid);

        vm.startBroadcast(account);
        VRFCoordinatorV2_5Mock(vrfCoordinator).addConsumer(subscriptionId, contractToAddToVrf);
        vm.stopBroadcast();

    }

    function run() external {
        address mostRecentDeployed = DevOpsTools.get_most_recent_deployment("Raffle", block.chainid);
        addConsumerUsingConfig(mostRecentDeployed);
    }

}