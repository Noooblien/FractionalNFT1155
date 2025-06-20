// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// @title FractionalNFT1155
// @notice Production-grade ERC-1155 contract for fractionalizing property unit NFTs
// @dev Supports variable shares, owner-only transfers with 48-hour approval expiry, upgradability, pausability, and role-based access control
contract FractionalNFT1155 is
    Initializable,
    ERC1155Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    // @notice Maximum shares per NFT to prevent gas issues
    uint256 public constant MAX_SHARES = 1_000_000;
    // @notice Approval expiry duration (48 hours in seconds)
    uint256 public constant APPROVAL_EXPIRY = 48 * 60 * 60;
    // @notice Maximum number of fraction owners per NFT to optimize gas
    uint256 public constant MAX_FRACTION_OWNERS = 50;

    // @notice Role for admin operations (e.g., pausing, upgrading)
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    // @notice Role for minting NFTs
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // @notice Struct to store fraction ownership
    struct Fraction {
        address owner; // Address of the fraction owner
        uint256 shares; // Number of shares owned
    }

    // @notice Struct to store approval details
    struct Approval {
        uint256 shares; // Number of approved shares
        uint256 expiry; // Expiry timestamp for the approval
    }

    // @notice Mapping: tokenId => total shares for the NFT
    mapping(uint256 => uint256) public totalShares;
    // @notice Mapping: tokenId => array of fractions
    mapping(uint256 => Fraction[]) public fractions;
    // @notice Mapping: tokenId => isFractionalized
    mapping(uint256 => bool) public isFractionalized;
    // @notice Mapping: tokenId => owner => approval details
    mapping(uint256 => mapping(address => Approval)) public fractionApprovals;

    // @notice Emitted when the contract is deployed or initialized
    event ContractInitialized(string uri, address indexed admin);
    // @notice Emitted when an NFT is minted
    event NFTMinted(uint256 indexed tokenId, address indexed to);
    // @notice Emitted when an NFT is fractionalized
    event Fractionalized(uint256 indexed tokenId, uint256 shares);
    // @notice Emitted when fractions are approved for transfer
    event FractionApproved(uint256 indexed tokenId, address indexed owner, uint256 shares);
    // @notice Emitted when fraction approval is revoked
    event FractionApprovalRevoked(uint256 indexed tokenId, address indexed owner);
    // @notice Emitted when fractions are transferred
    event FractionTransferred(uint256 indexed tokenId, address indexed from, address indexed to, uint256 shares);
    // @notice Emitted when an NFT is redeemed
    event Redeemed(uint256 indexed tokenId);
    // @notice Emitted when tokens/NFTs are recovered
    event TokensRecovered(address indexed token, address indexed to, uint256 amount, uint256 tokenId);

    // @dev Prevent direct initialization of implementation contract
    constructor() {
        _disableInitializers();
    }

    // @notice Initialize the contract (called once during deployment)
    // @param uri_ Base URI for token metadata
    function initialize(string memory uri_) external initializer {
        __ERC1155_init(uri_);
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        // Set deployer as admin and minter
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);

        require(msg.sender != address(0), "Deployer cannot be zero address");
        emit ContractInitialized(uri_, msg.sender);
    }

    // @notice Override supportsInterface to resolve inheritance conflict
    // @param interfaceId The interface ID to check
    // @return bool True if the interface is supported
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return
            ERC1155Upgradeable.supportsInterface(interfaceId) ||
            AccessControlUpgradeable.supportsInterface(interfaceId);
    }

    // @dev Authorize contract upgrades (only admin)
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

    // @notice Mint and fractionalize an NFT in one step
    // @param tokenId Unique ID for the NFT
    // @param to Recipient of the shares
    // @param shares Number of shares to fractionalize
    function mintAndFractionalize(
        uint256 tokenId,
        address to,
        uint256 shares
    ) external onlyRole(MINTER_ROLE) whenNotPaused nonReentrant {
        require(to != address(0), "Invalid recipient address");
        require(balanceOf(to, tokenId) == 0, "Token already minted");
        require(!isFractionalized[tokenId], "Already fractionalized");
        require(shares > 0, "Shares must be greater than 0");
        require(shares <= MAX_SHARES, "Exceeds maximum shares");

        // Mint NFT to contract (locked)
        _mint(address(this), tokenId, 1, "");

        // Set fractionalization state
        isFractionalized[tokenId] = true;
        totalShares[tokenId] = shares;

        // Assign shares to recipient
        fractions[tokenId].push(Fraction(to, shares));

        emit NFTMinted(tokenId, to);
        emit Fractionalized(tokenId, shares);
    }

    // @notice Batch mint and fractionalize multiple NFTs
    // @param tokenIds Array of token IDs
    // @param to Array of recipients
    // @param shares Array of share counts
    function batchMintAndFractionalize(
        uint256[] calldata tokenIds,
        address[] calldata to,
        uint256[] calldata shares
    ) external onlyRole(MINTER_ROLE) whenNotPaused nonReentrant {
        require(tokenIds.length == to.length && to.length == shares.length, "Array length mismatch");
        require(tokenIds.length <= 50, "Too many tokens");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(to[i] != address(0), "Invalid recipient address");
            require(balanceOf(to[i], tokenIds[i]) == 0, "Token already minted");
            require(!isFractionalized[tokenIds[i]], "Already fractionalized");
            require(shares[i] > 0, "Shares must be greater than 0");
            require(shares[i] <= MAX_SHARES, "Exceeds maximum shares");

            // Mint NFT to contract
            _mint(address(this), tokenIds[i], 1, "");

            // Set fractionalization state
            isFractionalized[tokenIds[i]] = true;
            totalShares[tokenIds[i]] = shares[i];

            // Assign shares
            fractions[tokenIds[i]].push(Fraction(to[i], shares[i]));

            emit NFTMinted(tokenIds[i], to[i]);
            emit Fractionalized(tokenIds[i], shares[i]);
        }
    }

    // @notice Approve contract owner to transfer fractions
    // @param tokenId NFT token ID
    // @param shares Number of shares to approve
    function approveFractionTransfer(uint256 tokenId, uint256 shares) external whenNotPaused nonReentrant {
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

    // @notice Revoke approval for fraction transfers
    // @param tokenId NFT token ID
    function revokeFractionApproval(uint256 tokenId) external whenNotPaused nonReentrant {
        require(isFractionalized[tokenId], "NFT not fractionalized");
        require(fractionApprovals[tokenId][msg.sender].shares > 0, "No approval to revoke");

        delete fractionApprovals[tokenId][msg.sender];

        emit FractionApprovalRevoked(tokenId, msg.sender);
    }

    // @notice Transfer approved fractions (owner-only)
    // @param tokenId NFT token ID
    // @param from Current fraction owner
    // @param to Recipient of shares
    // @param shares Number of shares to transfer
    function transferFractionAsOwner(
        uint256 tokenId,
        address from,
        address to,
        uint256 shares
    ) external onlyRole(ADMIN_ROLE) whenNotPaused nonReentrant {
        require(isFractionalized[tokenId], "NFT not fractionalized");
        require(shares > 0 && shares <= totalShares[tokenId], "Invalid share amount");
        require(to != address(0), "Invalid recipient address");
        require(fractions[tokenId].length < MAX_FRACTION_OWNERS, "Too many fraction owners");

        Approval memory approval = fractionApprovals[tokenId][from];
        require(approval.shares >= shares, "Not enough approved shares");
        require(approval.expiry >= block.timestamp, "Approval expired");

        uint256 senderIndex = _findFractionIndex(tokenId, from);
        require(senderIndex < fractions[tokenId].length, "Sender has no shares");
        require(fractions[tokenId][senderIndex].shares >= shares, "Insufficient shares");

        // Update sender's shares
        fractions[tokenId][senderIndex].shares -= shares;
        // Update approval
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

    // @notice Redeem NFT by owning all fractions
    // @param tokenId NFT token ID
    function redeemNFT(uint256 tokenId) external whenNotPaused nonReentrant {
        require(isFractionalized[tokenId], "NFT not fractionalized");
        uint256 senderIndex = _findFractionIndex(tokenId, msg.sender);
        require(senderIndex < fractions[tokenId].length, "Sender has no shares");
        require(
            fractions[tokenId][senderIndex].shares == totalShares[tokenId],
            "Must own all fractions"
        );

        // Reset fractional data
        isFractionalized[tokenId] = false;
        totalShares[tokenId] = 0;
        delete fractions[tokenId];

        // Transfer NFT to redeemer
        _safeTransferFrom(address(this), msg.sender, tokenId, 1, "");

        emit Redeemed(tokenId);
    }

    // @notice Get fraction owners for a tokenId
    // @param tokenId NFT token ID
    // @return Array of fraction owners and their shares
    function getFractionOwners(uint256 tokenId) external view returns (Fraction[] memory) {
        require(isFractionalized[tokenId], "NFT not fractionalized");
        return fractions[tokenId];
    }

    // @notice Pause the contract (admin-only)
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    // @notice Unpause the contract (admin-only)
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // @notice Recover stuck tokens or NFTs (admin-only)
    // @param tokenAddress Address of the token contract (0x0 for ETH)
    // @param to Recipient address
    // @param amount Amount to recover (for ERC-20/ETH) or tokenId (for ERC-1155)
    function recoverTokens(
        address tokenAddress,
        address to,
        uint256 amount,
        uint256 tokenId
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        require(to != address(0), "Invalid recipient address");

        if (tokenAddress == address(0)) {
            // Recover ETH
            (bool success, ) = to.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else if (tokenAddress == address(this)) {
            // Recover ERC-1155
            _safeTransferFrom(address(this), to, tokenId, amount, "");
        } else {
            // Recover ERC-20
            (bool success, bytes memory data) = tokenAddress.call(
                abi.encodeWithSelector(0xa9059cbb, to, amount)
            );
            require(success && (data.length == 0 || abi.decode(data, (bool))), "Token transfer failed");
        }

        emit TokensRecovered(tokenAddress, to, amount, tokenId);
    }

    // @notice Helper function to find fraction index
    // @param tokenId NFT token ID
    // @param owner Address to find
    // @return Index in fractions array or array length if not found
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

    // @dev Prevent direct transfers
    function safeTransferFrom(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual override {
        revert("Direct transfers not allowed; use transferFractionAsOwner");
    }

    // @dev Handle ERC-1155 receipt
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }
}