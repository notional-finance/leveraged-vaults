// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

enum CurveInterface {
    V1,
    V2,
    StableSwapNG
}

interface ICurvePool {
    function coins(uint256 idx) external view returns (address);

    // @notice Perform an exchange between two coins
    // @dev Index values can be found via the `coins` public getter method
    // @dev see: https://etherscan.io/address/0xDC24316b9AE028F1497c275EB9192a3Ea0f67022#readContract
    // @param i Index value for the stEth to send -- 1
    // @param j Index value of the Eth to recieve -- 0
    // @param dx Amount of `i` (stEth) being exchanged
    // @param minDy Minimum amount of `j` (Eth) to receive
    // @return Actual amount of `j` (Eth) received
    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 minDy
    ) external payable returns (uint256);

    function balances(uint256 i) external view returns (uint256);

    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
}

interface ICurvePoolV1 is ICurvePool {
    function lp_token() external view returns (address);
}

interface ICurvePoolV2 is ICurvePool {
    function token() external view returns (address);
}

interface ICurve2TokenPoolV1 is ICurvePoolV1 {
    function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount) external payable returns (uint256);
    function remove_liquidity(uint256 amount, uint256[2] calldata _min_amounts) external returns (uint256[2] memory);
    function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 _min_amount) external returns (uint256);
}

interface ICurve2TokenPoolV2 is ICurvePoolV2 {
    function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount, bool use_eth) external payable returns (uint256);
    function remove_liquidity_one_coin(uint256 token_amount, uint256 i, uint256 min_amount, bool use_eth, address receiver) external returns (uint256);
    // Curve V2 does not return the amounts removed
    function remove_liquidity(uint256 amount, uint256[2] calldata _min_amounts, bool use_eth, address receiver) external;
}

interface ICurveStableSwapNG is ICurvePoolV1 {
    function add_liquidity(uint256[] calldata amounts, uint256 min_mint_amount) external payable returns (uint256);
    function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 _min_amount) external returns (uint256);
    function remove_liquidity(uint256 amount, uint256[] calldata _min_amounts) external returns (uint256[] memory);
    function totalSupply() external view returns (uint256);
}