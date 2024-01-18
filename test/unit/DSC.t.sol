// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {DSC} from "../../src/DSC.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract DSCTest is StdCheats, Test {
    DSC dsc;

    function setUp() public {
        dsc = new DSC();
    }

    // ================================================================
    // │                          MINT TESTS                          │
    // ================================================================
    function test_CanMint() public {
        vm.prank(dsc.owner());
        dsc.mint(address(this), 100);
        assertEq(dsc.balanceOf(address(this)), 100);
    }

    function test_CantMintToZeroAddress() public {
        vm.prank(dsc.owner());
        vm.expectRevert(DSC.DSC__MintNotZeroAddress.selector);
        dsc.mint(address(0), 100);
    }

    function test_MustMintMoreThanZero() public {
        vm.prank(dsc.owner());
        vm.expectRevert(DSC.DSC__MintAmountMustBeMoreThanZero.selector);
        dsc.mint(address(this), 0);
    }

    // ================================================================
    // │                          BURN TESTS                          │
    // ================================================================
    function test_CanBurn() public {
        vm.startPrank(dsc.owner());
        dsc.mint(address(this), 100);
        dsc.burn(50);
        vm.stopPrank();
        assertEq(dsc.balanceOf(address(this)), 50);
    }

    function test_MustBurnMoreThanZero() public {
        vm.prank(dsc.owner());
        vm.expectRevert(DSC.DSC__BurnAmountMustBeMoreThanZero.selector);
        dsc.burn(0);
    }

    function test_CantBurnMoreThanYouHave() public {
        vm.startPrank(dsc.owner());
        dsc.mint(address(this), 100);
        vm.expectRevert(DSC.DSC__BurnAmountExceedsBalance.selector);
        dsc.burn(101);
        vm.stopPrank();
    }
}
