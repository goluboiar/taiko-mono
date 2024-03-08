// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../tiers/ITierProvider.sol";
import "../ITaikoL1.sol";
import "./Guardians.sol";

/// @title GuardianProver
/// @custom:security-contact security@taiko.xyz
contract GuardianProver is Guardians {
    using ECDSA for bytes32;

    uint256[50] private __gap;

    /// @notice Emitted when a guardian proof is approved.
    /// @param addr The address of the guardian.
    /// @param blockId The block ID.
    /// @param blockHash The block hash.
    /// @param approved If the proof is approved.
    event GuardianApproval(
        address indexed addr, uint256 indexed blockId, bytes32 blockHash, bool approved
    );

    /// @notice Initializes the contract.
    /// @param _owner The owner of this contract. msg.sender will be used if this value is zero.
    /// @param _addressManager The address of the {AddressManager} contract.
    function init(address _owner, address _addressManager) external initializer {
        __Essential_init(_owner, _addressManager);
    }

    /// @dev Called by guardians to approve a guardian proof
    /// @param _meta The block's metadata.
    /// @param _tran The valid transition.
    /// @param _proof The tier proof.
    /// @return approved_ If the minimum number of participants sent the same proof, and proving
    /// transaction is fired away returns true, false otherwise.
    function approve(
        TaikoData.BlockMetadata calldata _meta,
        TaikoData.Transition calldata _tran,
        TaikoData.TierProof calldata _proof
    )
        external
        whenNotPaused
        nonReentrant
        returns (bool approved_)
    {
        if (_proof.tier != LibTiers.TIER_GUARDIAN) revert INVALID_PROOF();
        bytes32 hash = keccak256(abi.encode(_meta, _tran));
        approved_ = approve(_meta.id, hash);

        if (approved_) {
            deleteApproval(hash);
            ITaikoL1(resolve("taiko", false)).proveBlock(_meta.id, abi.encode(_meta, _tran, _proof));
        }

        emit GuardianApproval(msg.sender, _meta.id, _tran.blockHash, approved_);
    }

    /// @dev Called by guardians to approve a guardian proof with a list of signatures.
    /// @param _meta The block's metadata.
    /// @param _tran The valid transition.
    /// @param _proof The tier proof.
    /// @param _signatures The guardians' signatures.
    function approveWithSignatures(
        TaikoData.BlockMetadata calldata _meta,
        TaikoData.Transition calldata _tran,
        TaikoData.TierProof calldata _proof,
        bytes[] calldata _signatures
    )
        external
        whenNotPaused
        nonReentrant
    {
        if (_proof.tier != LibTiers.TIER_GUARDIAN) revert INVALID_PROOF();
        if (_signatures.length < MIN_NUM_GUARDIANS) revert INVALID_SIGNATURES();

        bytes32 hash = keccak256(abi.encode("APPROVE", _meta, _tran));
        address lastGuardian;

        for (uint256 i; i < MIN_NUM_GUARDIANS; ++i) {
            address guardian = hash.recover(_signatures[i]);
            if (uint160(guardian) <= uint160(lastGuardian) || guardianIds[guardian] == 0) {
                revert INVALID_SIGNATURES();
            }
            lastGuardian = guardian;
        }

        deleteApproval(hash);
        ITaikoL1(resolve("taiko", false)).proveBlock(_meta.id, abi.encode(_meta, _tran, _proof));

        emit GuardianApproval(address(0), _meta.id, _tran.blockHash, true);
    }
}
