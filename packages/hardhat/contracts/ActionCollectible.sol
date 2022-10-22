//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "base64-sol/base64.sol";
import "./ToColor.sol";
import {IERC5050Sender, IERC5050Receiver, Action} from "./interfaces/IERC5050.sol";
import {ActionsSet} from "./libraries/ActionsSet.sol";
import "./interfaces/IPublicLockV10.sol";

// GET LISTED ON OPENSEA: https://testnets.opensea.io/get-listed/step-two

contract ActionCollectible is
    IERC5050Sender,
    IERC5050Receiver,
    ERC721Enumerable,
    Ownable
{
    using Address for address;
    using Strings for uint256;
    using Strings for uint160;
    using ToColor for bytes3;
    using Counters for Counters.Counter;
    using ActionsSet for ActionsSet.Set;
    IPublicLock public publicLock;
    Counters.Counter private _tokenIds;

    constructor() ERC721("Loogies", "LOOG") {}

    mapping(uint256 => bytes3) public color;
    mapping(uint256 => uint256) public chubbiness;
    ActionsSet.Set private _receivableActions;
    ActionsSet.Set private _sendableActions;

    bytes32 private _hash;
    uint256 private _nonce;
    uint256 mintDeadline = block.timestamp + 24 hours;

    mapping(address => mapping(bytes4 => address)) actionApprovals;
    mapping(address => mapping(address => bool)) operatorApprovals;

    function setActionLock(IPublicLock _lockAddress) public onlyOwner {
        publicLock = _lockAddress;
    }

    function hasValidActionKey(address _user) public view returns (bool hasKey) {
        hasKey = publicLock.getHasValidKey(_user);
    }

    function mintItem() public returns (uint256) {
        require(block.timestamp < mintDeadline, "DONE MINTING");
        _tokenIds.increment();

        uint256 id = _tokenIds.current();
        _mint(msg.sender, id);

        bytes32 predictableRandom = keccak256(
            abi.encodePacked(
                blockhash(block.number - 1),
                msg.sender,
                address(this),
                id
            )
        );
        color[id] =
            bytes2(predictableRandom[0]) |
            (bytes2(predictableRandom[1]) >> 8) |
            (bytes3(predictableRandom[2]) >> 16);
        chubbiness[id] =
            35 +
            ((55 * uint256(uint8(predictableRandom[3]))) / 255);

        return id;
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        require(_exists(id), "not exist");
        string memory name = string(
            abi.encodePacked("Loogie #", id.toString())
        );
        //   string memory description = string(abi.encodePacked('This Loogie is the color #',color[id].toColor(),' with a chubbiness of ',chubbiness[id].toString(),'!!!'));
        string memory image = Base64.encode(bytes(generateSVGofTokenById(id)));

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name":"',
                                name,
                                //   '", "description":"',
                                //   description,
                                '", "external_url":"https://burnyboys.com/token/',
                                id.toString(),
                                '", "attributes": [{"trait_type": "color", "value": "#',
                                color[id].toColor(),
                                '"},{"trait_type": "chubbiness", "value": ',
                                chubbiness[id].toString(),
                                '}], "owner":"',
                                (uint160(ownerOf(id))).toHexString(20),
                                '", "image": "',
                                "data:image/svg+xml;base64,",
                                image,
                                '"}'
                            )
                        )
                    )
                )
            );
    }

    function generateSVGofTokenById(uint256 id)
        internal
        view
        returns (string memory)
    {
        string memory svg = string(
            abi.encodePacked(
                '<svg width="400" height="400" xmlns="http://www.w3.org/2000/svg">',
                renderTokenById(id),
                "</svg>"
            )
        );

        return svg;
    }

    // Visibility is `public` to enable it being called by other contracts for composition.
    function renderTokenById(uint256 id) public view returns (string memory) {
        string memory render = string(
            abi.encodePacked(
                '<g id="eye1">',
                '<ellipse stroke-width="3" ry="29.5" rx="29.5" id="svg_1" cy="154.5" cx="181.5" stroke="#000" fill="#fff"/>',
                '<ellipse ry="3.5" rx="2.5" id="svg_3" cy="154.5" cx="173.5" stroke-width="3" stroke="#000" fill="#000000"/>',
                "</g>",
                '<g id="head">',
                '<ellipse fill="#',
                color[id].toColor(),
                '" stroke-width="3" cx="204.5" cy="211.80065" id="svg_5" rx="',
                chubbiness[id].toString(),
                '" ry="51.80065" stroke="#000"/>',
                "</g>",
                '<g id="eye2">',
                '<ellipse stroke-width="3" ry="29.5" rx="29.5" id="svg_2" cy="168.5" cx="209.5" stroke="#000" fill="#fff"/>',
                '<ellipse ry="3.5" rx="3" id="svg_4" cy="169.5" cx="208" stroke-width="3" fill="#000000" stroke="#000"/>',
                "</g>"
            )
        );

        return render;
    }

    // function setProxyRegistry(address registry) external virtual onlyOwner {
    //     _setProxyRegistry(registry);
    // }

    function _registerAction(string memory action) internal {
        _registerSendable(action);
        _registerReceivable(action);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    // function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165) returns (bool) {
    //     return
    //         interfaceId == type(IERC5050Sender).interfaceId ||
    //         interfaceId == type(IERC5050Receiver).interfaceId ||
    //         super.supportsInterface(interfaceId);
    // }

    function receivableActions() external view returns (string[] memory) {
        return _receivableActions.names();
    }

    function onActionReceived(Action calldata action, uint256 nonce)
        external
        payable
        virtual
    {
        _onActionReceived(action, nonce);
    }

    function _onActionReceived(Action calldata action, uint256 nonce)
        internal
        virtual
    {
        // if (action.state != address(0)) {
        require(action.state != address(0), "Zero address state");
        address next = action.state;
        require(next.isContract(), "ERC5050: invalid state");
        try
            IERC5050Receiver(next).onActionReceived{value: msg.value}(
                action,
                nonce
            )
        {} catch (bytes memory reason) {
            if (reason.length == 0) {
                revert("ERC5050: call to non ERC5050Receiver");
            } else {
                assembly {
                    revert(add(32, reason), mload(reason))
                }
            }
        }
        // }
        // else {
        // Implement on state
        //     address next = action.to._address;
        //     require(next.isContract(), "ERC5050: invalid state");
        //     if (next == address(this)) {
        //         require(
        //             _receivableActions.contains(action.selector),
        //             "ERC5050: invalid action"
        //         );
        //         require(
        //             (action.from._address != address(0) &&
        //                 action.user == tx.origin) || action.user == msg.sender,
        //             "ERC5050: invalid sender"
        //         );
        //         // Do the action here

        //     }
        // }
        emit ActionReceived(
            action.selector,
            action.user,
            action.from._address,
            action.from._tokenId,
            action.to._address,
            action.to._tokenId,
            action.state,
            action.data
        );
    }

    function sendAction(Action memory action) external payable virtual {
        require(
            _sendableActions.contains(action.selector),
            "ERC5050: invalid action"
        );
        require(
            _isApprovedOrSelf(action.user, action.selector),
            "ERC5050: unapproved sender"
        );
        // require(
        //     action.from._address == address(this),
        //     "ERC5050: invalid from address"
        // );
        // require(
        //     hasValidActionKey(msg.sender),
        //     "Invalid key for action"
        // );
        _sendAction(action);
    }

    function isValid(bytes32 actionHash, uint256 nonce)
        external
        view
        returns (bool)
    {
        return actionHash == _hash && nonce == _nonce;
    }

    function sendableActions() external view returns (string[] memory) {
        return _sendableActions.names();
    }

    function approveForAction(
        address _account,
        bytes4 _action,
        address _approved
    ) public virtual returns (bool) {
        require(_approved != _account, "ERC5050: approve to caller");

        require(
            msg.sender == _account ||
                isApprovedForAllActions(_account, msg.sender),
            "ERC5050: approve caller is not account nor approved for all"
        );

        actionApprovals[_account][_action] = _approved;
        emit ApprovalForAction(_account, _action, _approved);

        return true;
    }

    function setApprovalForAllActions(address _operator, bool _approved)
        public
        virtual
    {
        require(msg.sender != _operator, "ERC5050: approve to caller");

        operatorApprovals[msg.sender][_operator] = _approved;

        emit ApprovalForAllActions(msg.sender, _operator, _approved);
    }

    function getApprovedForAction(address _account, bytes4 _action)
        public
        view
        returns (address)
    {
        return actionApprovals[_account][_action];
    }

    function isApprovedForAllActions(address _account, address _operator)
        public
        view
        returns (bool)
    {
        return operatorApprovals[_account][_operator];
    }

    function _sendAction(Action memory action) private {
        address next;
        bool toIsContract = action.to._address.isContract();
        bool stateIsContract = action.state.isContract();
        require(toIsContract, "Send Action: Invalid 'to' contract");
        require(stateIsContract, "Send Action: Invalid state");
        if (action.to._address == address(this)) {
            next = action.to._address;
        } else {
            next = action.state;
        }
        uint256 nonce;
        _validate(action);
        nonce = _nonce;
        try
            IERC5050Receiver(next).onActionReceived{value: msg.value}(
                action,
                nonce
            )
        {} catch Error(string memory err) {
            revert(err);
        } catch (bytes memory returnData) {
            if (returnData.length > 0) {
                revert(string(returnData));
            }
        }
        emit SendAction(
            action.selector,
            action.user,
            action.from._address,
            action.from._tokenId,
            action.to._address,
            action.to._tokenId,
            action.state,
            action.data
        );
    }

    function _validate(Action memory action) internal {
        ++_nonce;
        _hash = bytes32(
            keccak256(
                abi.encodePacked(
                    action.selector,
                    action.user,
                    action.from._address,
                    action.from._tokenId,
                    action.to._address,
                    action.to._tokenId,
                    action.state,
                    action.data,
                    _nonce
                )
            )
        );
    }

    function _isApprovedOrSelf(address account, bytes4 action)
        internal
        view
        returns (bool)
    {
        return (msg.sender == account ||
            isApprovedForAllActions(account, msg.sender) ||
            getApprovedForAction(account, action) == msg.sender);
    }

    function _registerSendable(string memory action) internal {
        _sendableActions.add(action);
    }

    function _registerReceivable(string memory action) internal {
        _receivableActions.add(action);
    }
}