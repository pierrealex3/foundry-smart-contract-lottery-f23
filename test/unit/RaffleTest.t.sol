// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Raffle} from "src/Raffle.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {CodeConstants} from "script/HelperConfig.s.sol";

contract RaffleTest is Test, CodeConstants {
    Raffle public raffle;
    HelperConfig public helperConfig;

    address public PLAYER = makeAddr("player");
    uint256 public STARTING_PLAYER_BALANCE = 10 ether;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint256 subscriptionId;
    uint32 callbackGasLimit;

    /** Events **/
    event EnteredRaffle(address indexed player);    


    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        subscriptionId = config.subscriptionId;
        callbackGasLimit = config.callbackGasLimit;

        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() ==  Raffle.RaffleState.OPEN);
    }

    function testEnterRaffleRevertsWhenYouDontPayEnough() public {
        // Arrange
        vm.prank(PLAYER);
        // Act/Assert
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();        
    }

    function testEnterRaffleRecordsPlayersWhenTheyEnter() public {
        // Arrange
        vm.prank(PLAYER);

        // Act
        raffle.enterRaffle{value: entranceFee}();  // enter the raffle the CORRECT way

        // Assert
        assertEq(raffle.getPlayer(0), PLAYER);
    }

    function testEnteredRaffleEventEmittedWhenPlayerEntersRaffle() public {
        // Arrange
        vm.prank(PLAYER);
                
        // Act/Assert
        vm.expectEmit(true, false, false, false, address(raffle));
        
        // we emit the event we expect to see.
        emit EnteredRaffle(PLAYER);

        raffle.enterRaffle{value: entranceFee}();  // enter the raffle the CORRECT way

    }

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();  // enter the raffle the CORRECT way
        
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        // Act/Assert        
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();  // enter the raffle the CORRECT way
    }

   /*********************************************
                  CHECK UPKEEP
   *********************************************/

   function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
      // Arrange
      // It has no balance because nobody enters the raffle...
      vm.prank(PLAYER);
      vm.warp(block.timestamp + interval + 1);
      vm.roll(block.number + 1);

      // Act/Assert
      (bool upkeepNeeded,) = raffle.checkUpkeep("");
      assert(!upkeepNeeded);
   }

   function testCheckUpkeepReturnsFalseIfRaffleIsntOpen() public {
        // Arrange
        // Raffle is not open because performUpkeep is called and therefore the state is CALCULATING...
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();  // enter the raffle the CORRECT way
        
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        // Act/Assert
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
   }

   /*********************************************
                  PERFORM UPKEEP
   *********************************************/

   function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
    // Arrange
    // do the minimum to make checkUpkeep return false - which is no one enters the raffle...
    uint256 currentBalance = 0;
    uint256 numPlayers = 0;
    Raffle.RaffleState rState = raffle.getRaffleState();

    // Act/Assert
    vm.expectRevert(
        abi.encodeWithSelector(
        Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, rState)
        );
    raffle.performUpkeep("");
   }

   function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
       // Arrange
       vm.prank(PLAYER);
       raffle.enterRaffle{value: entranceFee}();  // enter the raffle the CORRECT way
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

       // Act/Assert
       raffle.performUpkeep("");
   }

   modifier raffleEntered() {    
    vm.prank(PLAYER);
    raffle.enterRaffle{value: entranceFee}();  // enter the raffle the CORRECT way
    vm.warp(block.timestamp + interval + 1);
    vm.roll(block.number + 1);
    _;
   }

   function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEntered {
    // Arrange

    // Act
    vm.recordLogs(); // capture logs 
    raffle.performUpkeep("");

    Vm.Log[] memory entries = vm.getRecordedLogs();
    bytes32 requestId = entries[1].topics[1];  // topics[0] is always reserved for something else...  entries[1] because looking at the code sequence from performUpkeep, entries[0] is gonna come from the VrfCoordinator!

    // Assert
    Raffle.RaffleState raffleState = raffle.getRaffleState();
    assert(uint256(requestId) > 0);
    assert(uint256(raffleState) == 1);
   }

    /*********************************************
                  FULFILL RANDOM WORDS
   *********************************************/
   modifier skipFork() {
    if (block.chainid != LOCAL_CHAIN_ID) {
        return;
    }
    _;
   }

   /**
    * The strategy here is to expect a targeted revert to be done.
    * The revert is expected because the raffle contract's performUpkeep method is not called, and instead the vrfCoordinator (mocked) node calls the raffle contract's fulfillRandomWords method!
    * This targeted revert is initiated within VRFCoordinatorV2_5Mock.sol if the sequence of calls is not good.
    */
   function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId) public raffleEntered skipFork {
    // Arrange / Act / Assert
    vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
    VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));

   }

   function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEntered skipFork {
    // Arrange 

    // have 3 additional players enter the raffle to be more "realistic".
    uint256 additionalEntrants = 3; // 4 total
    uint256 startingIndex = 1;
    address expectedWinner = address(1); // we know this by looking at the VRFCoordinatorV2_5Mock.fulfillRandomWords code: the "random" word array given by the mock is actually [0, 1, 2, n].  Therefore, the modulus operation selecting our winner will fall on the player at index 1.

    for (uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) {
        address newPlayer = address(uint160(i));  // this is a natural way to build an address because an Ethereum addresses is a 20-byte (160-bits) value
        hoax(newPlayer, 1 ether);
        raffle.enterRaffle{value: entranceFee}();
    }

    uint256 startingTimeStamp = raffle.getLastTimeStamp();
    uint256 winnerStartingBalance = expectedWinner.balance;

    // Act

    // get the requestId that is required as a parameter to fulfillRandomWords
    vm.recordLogs(); // capture logs 
    raffle.performUpkeep("");
    Vm.Log[] memory entries = vm.getRecordedLogs();
    bytes32 requestId = entries[1].topics[1];

    // the strategy is to: call the deployed mock that will *in turn* call the Raffle contract method
    VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

    // Assert

    Raffle.RaffleState raffleState = raffle.getRaffleState();
    address recentWinner = raffle.getRecentWinner();
    uint256 winnerBalance = recentWinner.balance;
    uint256 enndingTimeStamp = raffle.getLastTimeStamp();
    uint256 winnerPrize = entranceFee * (additionalEntrants + 1);
    
    assert(raffleState == Raffle.RaffleState.OPEN);  // same as `assert(uint256(raffleState) == 0);`    
    assert(recentWinner == expectedWinner);    
    assert(winnerPrize == winnerBalance - winnerStartingBalance);
    assertEq(0, raffle.getPlayerCount());
    assert(enndingTimeStamp > startingTimeStamp);

   }

}

