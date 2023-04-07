// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "forge-std/Test.sol";
import { DeployFactory } from "script/ClaimsHatter.s.sol";
import { ClaimsHatter } from "src/ClaimsHatter.sol";
import { ClaimsHatterFactory } from "src/ClaimsHatterFactory.sol";
import { LibClone } from "solady/utils/LibClone.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";

contract ClaimsHatterFactoryTest is Test, DeployFactory {
  // variables inhereted from DeployFactory script
  // address public implementation;
  // address public factory;
  // address public hats;

  // other variables for testing
  uint256 public fork;
  uint256 public topHat1 = 0x0000000100000000000000000000000000000000000000000000000000000000;
  uint256 public hat1 = 0x0000000100010000000000000000000000000000000000000000000000000000;
  bytes32 maxBytes32 = bytes32(type(uint256).max);
  bytes largeBytes = abi.encodePacked("this is a fairly large bytes object");
  string public constant VERSION = "this is a test";

  event ClaimsHatterDeployed(uint256 hatId, address instance);

  error ClaimsHatterFactory_AlreadyDeployed(uint256 hatId);

  function setUp() public virtual {
    fork = vm.createFork(vm.envString("ETHEREUM_RPC"), 16_947_805);
    // use the fork (Luke)
    vm.selectFork(fork);
    // deploy the clone factory and the implementation contract
    DeployFactory.prepare(VERSION);
    DeployFactory.run();
  }
}

contract Deploy is ClaimsHatterFactoryTest {
  function test_deploy() public {
    assertEq(address(factory.HATS()), address(hats), "hats");
    assertEq(address(factory.IMPLEMENTATION()), address(implementation), "implementation");
    assertEq(implementation.version(), VERSION, "version");
    assertEq(factory.version(), VERSION, "factory version");
  }
}

/// @notice Harness contract to test ClaimsHatterFactory's internal functions
contract FactoryHarness is ClaimsHatterFactory {
  constructor(ClaimsHatter _implementation, IHats _hats, string memory _version)
    ClaimsHatterFactory(_implementation, _hats, _version)
  { }

  function encodeArgs(uint256 _hatId) public view returns (bytes memory) {
    return _encodeArgs(_hatId);
  }

  function calculateSalt(bytes memory args) public view returns (bytes32) {
    return _calculateSalt(args);
  }

  function getClaimsHatterAddress(bytes memory _arg, bytes32 _salt) public view returns (address) {
    return _getClaimsHatterAddress(_arg, _salt);
  }

  function createHatter(uint256 _hatId) public returns (ClaimsHatter) {
    return _createClaimsHatter(_hatId);
  }
}

contract InternalTest is ClaimsHatterFactoryTest {
  FactoryHarness harness;

  function setUp() public virtual override {
    super.setUp();
    // deploy harness
    harness = new FactoryHarness(implementation, hats, "this is a test harness");
  }
}

contract Internal_encodeArgs is InternalTest {
  function test_fuzz_encodeArgs(uint256 _hatId) public {
    assertEq(harness.encodeArgs(_hatId), abi.encodePacked(address(harness), hats, _hatId), "encodeArgs");
  }

  function test_encodeArgs_0() public {
    test_fuzz_encodeArgs(0);
  }

  function test_encodeArgs_max() public {
    test_fuzz_encodeArgs(type(uint256).max);
  }

  function test_encodeArgs_validHat() public {
    test_fuzz_encodeArgs(hat1);
  }
}

contract Internal_calculateSalt is InternalTest {
  function test_fuzz_calculateSalt(bytes memory _args) public {
    assertEq(harness.calculateSalt(_args), keccak256(abi.encodePacked(_args, block.chainid)), "calculateSalt");
  }

  function test_calculateSalt_0() public {
    test_fuzz_calculateSalt(hex"00");
  }

  function test_calculateSalt_large() public {
    test_fuzz_calculateSalt(largeBytes);
  }

  function test_calculateSalt_validHat() public {
    test_fuzz_calculateSalt(harness.encodeArgs(hat1));
  }
}

contract Internal_getClaimsHatterAddress is InternalTest {
  function test_fuzz_getClaimsHatterAddress(bytes memory _arg, bytes32 _salt) public {
    assertEq(
      harness.getClaimsHatterAddress(_arg, _salt),
      LibClone.predictDeterministicAddress(address(implementation), _arg, _salt, address(harness))
    );
  }

  function test_getClaimsHatterAddress_0() public {
    test_fuzz_getClaimsHatterAddress(hex"00", hex"00");
  }

  function test_getClaimsHatterAddress_large() public {
    test_fuzz_getClaimsHatterAddress(largeBytes, maxBytes32);
  }

  function test_getClaimsHatterAddress_validHat() public {
    bytes memory args = harness.encodeArgs(hat1);
    test_fuzz_getClaimsHatterAddress(args, harness.calculateSalt(args));
  }
}

contract Internal_createHatter is InternalTest {
  function test_fuzz_createHatter(uint256 _hatId) public {
    bytes memory args = harness.encodeArgs(_hatId);
    ClaimsHatter hatter = harness.createHatter(_hatId);
    assertEq(address(hatter), harness.getClaimsHatterAddress(args, harness.calculateSalt(args)));
  }

  function test_createHatter_0() public {
    test_fuzz_createHatter(0);
  }
}

contract CreateClaimsHatter is ClaimsHatterFactoryTest {
  function test_fuzz_createClaimsHatter(uint256 _hatId) public {
    vm.assume(_hatId > 0); // hatId must be > 0

    vm.expectEmit(true, true, true, true);
    emit ClaimsHatterDeployed(_hatId, factory.getClaimsHatterAddress(_hatId));
    ClaimsHatter hatter = factory.createClaimsHatter(_hatId);
    assertEq(hatter.hat(), _hatId, "hat");
    assertEq(address(hatter.FACTORY()), address(factory), "FACTORY");
    assertEq(address(hatter.HATS()), address(hats), "HATS");
    assertFalse(hatter.claimable(), "claimable");
    assertFalse(hatter.claimableFor(), "claimableFor");
  }

  function test_createClaimsHatter_validHat() public {
    test_fuzz_createClaimsHatter(hat1);
  }

  function test_fuzz_createClaimsHatter_alreadyDeployed_reverts(uint256 _hatId) public {
    factory.createClaimsHatter(_hatId);
    vm.expectRevert(abi.encodeWithSelector(ClaimsHatterFactory_AlreadyDeployed.selector, _hatId));
    factory.createClaimsHatter(_hatId);
  }
}

contract GetClaimsHatterAddress is ClaimsHatterFactoryTest {
  function test_fuzz_getClaimsHatterAddress(uint256 _hatId) public {
    bytes memory args = abi.encodePacked(address(factory), address(hats), _hatId);
    address expected = LibClone.predictDeterministicAddress(
      address(implementation), args, keccak256(abi.encodePacked(args, block.chainid)), address(factory)
    );
    assertEq(factory.getClaimsHatterAddress(_hatId), expected);
  }

  function test_getClaimsHatterAddress_validHat() public {
    test_fuzz_getClaimsHatterAddress(hat1);
  }
}

contract Deployed is InternalTest {
  // uses the FactoryHarness version for easy access to the internal _createClaimsHatter function
  function test_fuzz_deployed_true(uint256 _hatId) public {
    harness.createHatter(_hatId);
    assertTrue(harness.deployed(_hatId));
  }

  function test_fuzz_deployed_false(uint256 _hatId) public {
    assertFalse(harness.deployed(_hatId));
  }
}
