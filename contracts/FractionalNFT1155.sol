// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// FractionalNFT1155: An ERC-1155 contract for fractionalizing property unit NFTs
// Features: Mint and fractionalize in one step, owner-restricted transfers with 48-hour approval expiry, testnet-ready
contract FractionalNFT1155 is ERC1155, Ownable, ReentrancyGuard {
    // Maximum shares per NFT to prevent gas issues
    uint256 public constant MAX_SHARES = 1_000_000;
    // Approval expiry duration (48 hours in seconds)
    uint256 public constant APPROVAL_EXPIRY = 48 * 60 * 60;

    // Struct to store fraction ownership
    struct Fraction {
        address owner; // Address of the fraction owner
        uint256 shares; // Number of shares owned
    }

    // Struct to store approval details
    struct Approval {
        uint256 shares; // Number of approved shares
        uint256 expiry; // Expiry timestamp for the approval
    }

    // Mapping: tokenId => total shares for the NFT
    mapping(uint256 => uint256) public totalShares;
    // Mapping: tokenId => array of fractions
    mapping(uint256 => Fraction[]) public fractions;
    // Mapping: tokenId => isFractionalized
    mapping(uint256 => bool) public isFractionalized;
    // Mapping: tokenId => owner => approval details
    mapping(uint256 => mapping(address => Approval)) public fractionApprovals;

    // Constructor: Initialize ERC-1155 with URI and set contract owner
    // URI can be a base URI (e.g., "https://api.example.com/token/{id}")
    constructor(string memory uri_)
        ERC1155(uri_)
        Ownable(msg.sender)
    {
        // Ensure deployer is not the zero address
        require(msg.sender != address(0), "Deployer cannot be zero address");
        emit ContractDeployed(uri_, msg.sender);
    }

    // Mint a new NFT and fractionalize it in one step
    // Prompts for tokenId, recipient address, and total shares
    function mintAndFractionalize(
        uint256 tokenId,
        address to,
        uint256 shares
    ) external onlyOwner nonReentrant {
        require(to != address(0), "Invalid recipient address");
        require(balanceOf(to, tokenId) == 0, "Token already minted");
        require(!isFractionalized[tokenId], "Already fractionalized");
        require(shares > 0, "Shares must be greater than 0");
        require(shares <= MAX_SHARES, "Exceeds maximum shares");

        // Mint NFT with supply of 1 to the contract (locked)
        _mint(address(this), tokenId, 1, "");

        // Set fractionalization state
        isFractionalized[tokenId] = true;
        totalShares[tokenId] = shares;

        // Assign all shares to the recipient
        fractions[tokenId].push(Fraction(to, shares));

        emit NFTMinted(tokenId, to);
        emit Fractionalized(tokenId, shares);
    }

    // Approve contract owner to transfer a specific number of fractions
    // Approval expires after 48 hours
    function approveFractionTransfer(uint256 tokenId, uint256 shares) external nonReentrant {
        require(isFractionalized[tokenId], "NFT not fractionalized");
        require(shares > 0, "Shares must be greater than 0");

        uint256 senderIndex = _findFractionIndex(tokenId, msg.sender);
        require(senderIndex < fractions[tokenId].length, "Sender has no shares");
        require(fractions[tokenId][senderIndex].shares >= shares, "Insufficient shares");

        fractionApprovals[tokenId][msg.sender] = Approval({
            shares: shares,
            expiry: block.timestamp + APPROVAL_EXPIRY
        });

        emit FractionApproved(tokenId, msg.sender, shares);
    }

    // Revoke approval for contract owner to transfer fractions
    function revokeFractionApproval(uint256 tokenId) external nonReentrant {
        require(isFractionalized[tokenId], "NFT not fractionalized");
        require(fractionApprovals[tokenId][msg.sender].shares > 0, "No approval to revoke");

        delete fractionApprovals[tokenId][msg.sender];

        emit FractionApprovalRevoked(tokenId, msg.sender);
    }

    // Contract owner transfers approved fractions from one user to another
    // Requires valid, non-expired approval
    function transferFractionAsOwner(
        uint256 tokenId,
        address from,
        address to,
        uint256 shares
    ) external onlyOwner nonReentrant {
        require(isFractionalized[tokenId], "NFT not fractionalized");
        require(shares > 0 && shares <= totalShares[tokenId], "Invalid share amount");
        require(to != address(0), "Invalid recipient address");

        Approval memory approval = fractionApprovals[tokenId][from];
        require(approval.shares >= shares, "Not enough approved shares");
        require(approval.expiry >= block.timestamp, "Approval expired");

        uint256 senderIndex = _findFractionIndex(tokenId, from);
        require(senderIndex < fractions[tokenId].length, "Sender has no shares");
        require(fractions[tokenId][senderIndex].shares >= shares, "Insufficient shares");

        // Update sender's shares
        fractions[tokenId][senderIndex].shares -= shares;
        // Update approval (reduce or clear)
        if (approval.shares == shares) {
            delete fractionApprovals[tokenId][from];
        } else {
            fractionApprovals[tokenId][from].shares -= shares;
        }

        // Add or update recipient's shares
        uint256 recipientIndex = _findFractionIndex(tokenId, to);
        if (recipientIndex < fractions[tokenId].length) {
            fractions[tokenId][recipientIndex].shares += shares;
        } else {
            fractions[tokenId].push(Fraction(to, shares));
        }

        // Clean up if sender has no shares
        if (fractions[tokenId][senderIndex].shares == 0) {
            fractions[tokenId][senderIndex] = fractions[tokenId][fractions[tokenId].length - 1];
            fractions[tokenId].pop();
        }

        emit FractionTransferred(tokenId, from, to, shares);
    }

 

    // Get list of fraction owners for a tokenId
    // Useful for front-end or testing
    function getFractionOwners(uint256 tokenId) external view returns (Fraction[] memory) {
        require(isFractionalized[tokenId], "NFT not fractionalized");
        return fractions[tokenId];
    }

    // Get contract owner for debugging
    function getContractOwner() external view returns (address) {
        return owner();
    }

    // Helper function to find fraction index for an owner
    // Returns array length if not found
    function _findFractionIndex(uint256 tokenId, address owner) internal view returns (uint256) {
        unchecked {
            for (uint256 i = 0; i < fractions[tokenId].length; i++) {
                if (fractions[tokenId][i].owner == owner) {
                    return i;
                }
            }
        }
        return fractions[tokenId].length;
    }

    // Implement IERC1155Receiver: Handle receipt of ERC-1155 tokens
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    // Prevent direct fraction transfers (not used, as transfers are owner-only)
    // This ensures users like Wallet A/B cannot transfer directly
    function safeTransferFrom(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual override {
        revert("Direct transfers not allowed; use transferFractionAsOwner");
    }

    // Events for tracking state changes
    event ContractDeployed(string uri, address indexed owner);
    event NFTMinted(uint256 indexed tokenId, address indexed to);
    event Fractionalized(uint256 indexed tokenId, uint256 shares);
    event FractionApproved(uint256 indexed tokenId, address indexed owner, uint256 shares);
    event FractionApprovalRevoked(uint256 indexed tokenId, address indexed owner);
    event FractionTransferred(uint256 indexed tokenId, address indexed from, address indexed to, uint256 shares);
    event Redeemed(uint256 indexed tokenId);
}

