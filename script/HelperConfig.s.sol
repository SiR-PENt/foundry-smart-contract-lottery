// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { Script } from "forge-std/Script.sol";
import { Raffle } from "../src/Raffle.sol";
import { VRFCoordinatorV2Mock } from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";
import { LinkToken } from "../test/mocks/LinkToken.sol";

contract HelperConfig is Script {

    struct NetworkConfig {
        uint256 entranceFee; 
        uint256 interval;
        address vrfCoordinator; 
        bytes32 gasLane;
        uint64 subscriptionId; 
        uint32 callbackGasLimit;
        address link; 
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if(block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        }
        else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            entranceFee: 0.01 ether,
            interval: 30,
            vrfCoordinator: 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625,
            gasLane: 0x8af398995b04c28e9951adb9721ef74c74f93e6a478f39e7e0777be13527e7ef,
            subscriptionId: 0, // we are gonna update this with the subId layher
            callbackGasLimit: 500000, // 500,000 should be more than enough
            link: 0x779877A7B0D9E8603169DdbD7836e478b4624789 //address to get link token on sepolia
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if(activeNetworkConfig.vrfCoordinator != address(0)) {
            return activeNetworkConfig;
        } // this condition is checking if activeNetworkConfig has been populated before running any mock
        
        uint96 baseFee = 0.25 ether; //0.25 LINK: this is the amount in gas you pay anytime the chainlink nodes call fulfill random words
        uint96 gasPriceLink = 1e9; // this is where the baseFee gets reimbursed from 
        vm.startBroadcast();
        VRFCoordinatorV2Mock vrfCoordinatorMock = new VRFCoordinatorV2Mock(baseFee, gasPriceLink);
        LinkToken link = new LinkToken();
        vm.stopBroadcast();
        
        return NetworkConfig({
            entranceFee: 0.01 ether,
            interval: 30,
            vrfCoordinator: address(vrfCoordinatorMock), //add a mock address for the vrfCoordinator
            gasLane: 0x8af398995b04c28e9951adb9721ef74c74f93e6a478f39e7e0777be13527e7ef,
            subscriptionId: 0, // we are gonna update this with the subId layher
            callbackGasLimit: 500000, // 500,000 should be more than enough
            link: address(link)
        });
    }
   
}

