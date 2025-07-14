// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "../script/Interactions.s.sol";
import {console} from "forge-std/console.sol"; // For debugging purposes, can be removed in production

contract DeployRaffle is Script {
    function run() external returns (Raffle) {}

    function deployContract() public returns (Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig(); // This comes with our mocks!
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        console.log("Account balance: ", config.account.balance);
        if (config.subscriptionId == 0) {
            CreateSubscription createSubscription = new CreateSubscription();
            (
                config.subscriptionId,
                config.vrfCoordinatorV2
            ) = createSubscription.createSubscription(
                config.vrfCoordinatorV2,
                config.account
            );

            // //Fund the subscription
            // FundSubscription fundSubscription = new FundSubscription();
            // fundSubscription.fundSubscription(
            //     config.vrfCoordinatorV2,
            //     config.subscriptionId,
            //     config.link
            // );
        }
        //Fund the subscription
        FundSubscription fundSubscription = new FundSubscription();
        fundSubscription.fundSubscription(
            config.vrfCoordinatorV2,
            config.subscriptionId,
            config.link,
            config.account
        );

        vm.startBroadcast(config.account);
        Raffle raffle = new Raffle(
            config.entranceFee,
            config.interval,
            config.vrfCoordinatorV2,
            config.gasLane,
            config.subscriptionId,
            config.callbackGasLimit
        );
        vm.stopBroadcast();

        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(
            address(raffle),
            config.vrfCoordinatorV2,
            config.subscriptionId,
            config.account
        );

        return (raffle, helperConfig);
    }
}
