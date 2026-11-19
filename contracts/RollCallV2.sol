// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal read interface for the official Agent ID NFT (SPACE ID Agent ID, ERC-721).
interface IAgentIDV2 {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title RollCallV2 — the daily Agent ID roll call, claim edition
/// @notice A daily check-in ritual exclusively for Agent ID holders on BNB Chain.
///         Every check-in IS a claim: answering today's roll call claims
///         RollCall Points (RC) into the caller's on-chain points balance.
///         There is NO claim fee of any kind — the only cost is the normal
///         BNB Chain network gas the user pays to the network, never to us.
///
/// @dev    POINTS MODEL (RC):
///         - RC are an internal, non-transferable points balance stored in
///           this contract (a mapping). RC are NOT an ERC-20 token, cannot be
///           transferred, traded, or withdrawn, and have no monetary value.
///           Nothing in this contract promises any exchange value, reward,
///           return, or income of any kind. RC are a presence/loyalty score.
///         - Base claim: 100 RC per daily check-in.
///         - Streak multiplier (applied to the streak AFTER today's check-in):
///             streak 1       -> 1.00x -> 100 RC
///             streak 2-3     -> 1.25x -> 125 RC
///             streak 4-6     -> 1.50x -> 150 RC
///             streak 7-13    -> 2.00x -> 200 RC
///             streak 14-29   -> 2.50x -> 250 RC
///             streak 30+     -> 3.00x -> 300 RC (cap)
///         - One claim per address per UTC day. Missing a day resets the
///           streak to 1 on the next check-in (same semantics as RollCall v1).
///
///         OWNER PERMISSIONS: NONE. This contract has no owner, no admin role,
///         no pause, no upgrade path, no mint authority beyond the claim rule
///         above, and no withdraw function. The Agent ID contract address is
///         set once in the constructor and is immutable. The contract is
///         non-payable and never holds, receives, or moves user assets.
contract RollCallV2 {
    /// @notice The official Agent ID contract on BNB Chain:
    ///         0x60b9262456de011f7d15a54cdd8c48baaa8b022f (set at deployment).
    IAgentIDV2 public immutable agentID;

    /// @notice Base points per daily claim, before the streak multiplier.
    uint256 public constant BASE_POINTS = 100;

    struct Agent {
        bool registered;
        uint256 registrationOrder; // 1-based position on the roll
        uint256 totalCheckIns;
        uint256 currentStreak;
        uint256 bestStreak;
        uint256 lastCheckInDay; // UTC day number (timestamp / 86400); 0 = never
        uint256 wavesReceived;
        uint256 points; // RC balance (non-transferable)
    }

    mapping(address => Agent) private _agents;
    mapping(uint256 => uint256) private _presentOnDay; // UTC day => agents present
    mapping(address => mapping(address => uint256)) private _lastWaveDayPlusOne; // from => to => UTC day + 1 (0 = never)

    uint256 public uniqueAgents;
    uint256 public totalCheckIns;
    uint256 public totalPointsIssued;

    event Registered(address indexed agent, uint256 registrationOrder);
    event CheckedIn(address indexed agent, uint256 indexed day, uint256 streak);
    event Claimed(address indexed agent, uint256 indexed day, uint256 streak, uint256 pointsAwarded, uint256 totalPoints);
    event Waved(address indexed from, address indexed to, uint256 indexed day);

    error NotAnAgent(address caller);
    error AlreadyCheckedInToday(address caller, uint256 day);
    error WaveTargetNotPresent(address target, uint256 day);
    error CannotWaveYourself();
    error AlreadyWavedToday(address from, address to, uint256 day);

    constructor(address agentIDContract) {
        require(agentIDContract != address(0), "agentID is zero address");
        agentID = IAgentIDV2(agentIDContract);
    }

    // ------------------------------------------------------------------ views

    function currentDay() public view returns (uint256) {
        return block.timestamp / 1 days;
    }

    /// @notice True if `account` currently holds at least one Agent ID.
    function isAgent(address account) public view returns (bool) {
        return agentID.balanceOf(account) > 0;
    }

    function hasCheckedInToday(address account) external view returns (bool) {
        return _agents[account].lastCheckInDay == currentDay() && _agents[account].totalCheckIns > 0;
    }

    function isRegistered(address account) external view returns (bool) {
        return _agents[account].registered;
    }

    function registrationOrderOf(address account) external view returns (uint256) {
        return _agents[account].registrationOrder;
    }

    function streakOf(address account) external view returns (uint256) {
        return _agents[account].currentStreak;
    }

    function bestStreakOf(address account) external view returns (uint256) {
        return _agents[account].bestStreak;
    }

    function checkInsOf(address account) external view returns (uint256) {
        return _agents[account].totalCheckIns;
    }

    function wavesReceivedOf(address account) external view returns (uint256) {
        return _agents[account].wavesReceived;
    }

    /// @notice RC points balance of `account` (non-transferable score).
    function pointsOf(address account) external view returns (uint256) {
        return _agents[account].points;
    }

    /// @notice UTC day number of the last successful check-in/claim (0 = never).
    function lastClaimDay(address account) external view returns (uint256) {
        return _agents[account].lastCheckInDay;
    }

    /// @notice Alias of lastClaimDay, kept for v1 naming parity.
    function lastCheckInDayOf(address account) external view returns (uint256) {
        return _agents[account].lastCheckInDay;
    }

    /// @notice Total unique claimers — alias of uniqueAgents().
    function totalClaimers() external view returns (uint256) {
        return uniqueAgents;
    }

    /// @notice True if `account` can claim right now: holds an Agent ID and
    ///         has not yet claimed today.
    function canClaimNow(address account) public view returns (bool) {
        if (!isAgent(account)) return false;
        Agent storage a = _agents[account];
        return !(a.totalCheckIns > 0 && a.lastCheckInDay == currentDay());
    }

    /// @notice Points awarded for a given (post-check-in) streak length.
    function pointsForStreak(uint256 streak) public pure returns (uint256) {
        if (streak == 0) return 0;
        if (streak == 1) return BASE_POINTS; // 1.00x -> 100
        if (streak <= 3) return 125; // 1.25x
        if (streak <= 6) return 150; // 1.50x
        if (streak <= 13) return 200; // 2.00x
        if (streak <= 29) return 250; // 2.50x
        return 300; // 3.00x cap, streak 30+
    }

    /// @notice The streak `account` would reach by claiming today
    ///         (0 if they have already claimed today).
    function nextStreakOf(address account) public view returns (uint256) {
        Agent storage a = _agents[account];
        uint256 day = currentDay();
        if (a.totalCheckIns > 0 && a.lastCheckInDay == day) return 0;
        if (a.totalCheckIns > 0 && a.lastCheckInDay == day - 1) return a.currentStreak + 1;
        return 1;
    }

    /// @notice Points `account` would receive for claiming today, including
    ///         the streak multiplier (0 if already claimed today).
    function claimableToday(address account) external view returns (uint256) {
        return pointsForStreak(nextStreakOf(account));
    }

    /// @notice How many agents are present on a given UTC day number.
    function presentOn(uint256 day) external view returns (uint256) {
        return _presentOnDay[day];
    }

    function presentToday() external view returns (uint256) {
        return _presentOnDay[currentDay()];
    }

    // ---------------------------------------------------------------- actions

    /// @notice Answer today's roll call AND claim today's RC points in one
    ///         transaction. Agent ID holders only, once per UTC day, no fee.
    function checkIn() external {
        _checkInAndClaim();
    }

    /// @notice Explicit alias of checkIn(): check-in + claim are one action.
    function checkInAndClaim() external {
        _checkInAndClaim();
    }

    function _checkInAndClaim() internal {
        if (!isAgent(msg.sender)) revert NotAnAgent(msg.sender);

        uint256 day = currentDay();
        Agent storage a = _agents[msg.sender];

        if (a.totalCheckIns > 0 && a.lastCheckInDay == day) {
            revert AlreadyCheckedInToday(msg.sender, day);
        }

        // Effects: registration (first claim only).
        if (!a.registered) {
            a.registered = true;
            uniqueAgents += 1;
            a.registrationOrder = uniqueAgents;
            emit Registered(msg.sender, uniqueAgents);
        }

        // Streak: yesterday -> extend, anything older (or first time) -> restart at 1.
        uint256 newStreak;
        if (a.totalCheckIns > 0 && a.lastCheckInDay == day - 1) {
            newStreak = a.currentStreak + 1;
        } else {
            newStreak = 1;
        }
        a.currentStreak = newStreak;
        if (newStreak > a.bestStreak) a.bestStreak = newStreak;

        uint256 awarded = pointsForStreak(newStreak);
        a.points += awarded;
        totalPointsIssued += awarded;

        a.lastCheckInDay = day;
        a.totalCheckIns += 1;
        totalCheckIns += 1;
        _presentOnDay[day] += 1;

        emit CheckedIn(msg.sender, day, newStreak);
        emit Claimed(msg.sender, day, newStreak, awarded, a.points);
    }

    /// @notice Wave at another agent who is present today. Agent ID holders only,
    ///         one wave per (sender, target) pair per UTC day. Purely a social
    ///         counter — waves carry no value and unlock nothing.
    function wave(address to) external {
        if (!isAgent(msg.sender)) revert NotAnAgent(msg.sender);
        if (to == msg.sender) revert CannotWaveYourself();

        uint256 day = currentDay();
        if (!(_agents[to].totalCheckIns > 0 && _agents[to].lastCheckInDay == day)) {
            revert WaveTargetNotPresent(to, day);
        }
        if (_lastWaveDayPlusOne[msg.sender][to] == day + 1) {
            revert AlreadyWavedToday(msg.sender, to, day);
        }

        _lastWaveDayPlusOne[msg.sender][to] = day + 1;
        _agents[to].wavesReceived += 1;

        emit Waved(msg.sender, to, day);
    }
}
