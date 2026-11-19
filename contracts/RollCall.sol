// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal read interface for the official Agent ID NFT (SPACE ID Agent ID, ERC-721).
interface IAgentID {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title RollCall — the daily Agent ID roll call
/// @notice A daily check-in ritual exclusively for Agent ID holders on BNB Chain.
///         Every state-changing function requires the caller to hold an Agent ID
///         (checked live against the official Agent ID contract).
///
/// @dev    OWNER PERMISSIONS: NONE. This contract has no owner, no admin role,
///         no pause, no upgrade path, and no withdraw function. The Agent ID
///         contract address is set once in the constructor and is immutable.
///         The contract is non-payable and never holds, receives, or moves
///         user assets. It stores counters only (registrations, check-ins,
///         streaks, waves). Counters have no monetary value and nothing in
///         this contract promises any return of any kind.
contract RollCall {
    /// @notice The official Agent ID contract on BNB Chain:
    ///         0x60b9262456de011f7d15a54cdd8c48baaa8b022f (set at deployment).
    IAgentID public immutable agentID;

    struct Agent {
        bool registered;
        uint256 registrationOrder; // 1-based position on the roll
        uint256 totalCheckIns;
        uint256 currentStreak;
        uint256 bestStreak;
        uint256 lastCheckInDay; // UTC day number (timestamp / 86400); type(uint256).max = never
        uint256 wavesReceived;
    }

    mapping(address => Agent) private _agents;
    mapping(uint256 => uint256) private _presentOnDay; // UTC day => agents present
    mapping(address => mapping(address => uint256)) private _lastWaveDayPlusOne; // from => to => UTC day + 1 (0 = never)

    uint256 public uniqueAgents;
    uint256 public totalCheckIns;

    event Registered(address indexed agent, uint256 registrationOrder);
    event CheckedIn(address indexed agent, uint256 indexed day, uint256 streak);
    event Waved(address indexed from, address indexed to, uint256 indexed day);

    error NotAnAgent(address caller);
    error AlreadyCheckedInToday(address caller, uint256 day);
    error WaveTargetNotPresent(address target, uint256 day);
    error CannotWaveYourself();
    error AlreadyWavedToday(address from, address to, uint256 day);

    constructor(address agentIDContract) {
        require(agentIDContract != address(0), "agentID is zero address");
        agentID = IAgentID(agentIDContract);
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
        return _agents[account].lastCheckInDay == currentDay();
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

    /// @notice How many agents are present on a given UTC day number.
    function presentOn(uint256 day) external view returns (uint256) {
        return _presentOnDay[day];
    }

    function presentToday() external view returns (uint256) {
        return _presentOnDay[currentDay()];
    }

    // ---------------------------------------------------------------- actions

    /// @notice Answer today's roll call. Agent ID holders only, once per UTC day.
    function checkIn() external {
        if (!isAgent(msg.sender)) revert NotAnAgent(msg.sender);

        uint256 day = currentDay();
        Agent storage a = _agents[msg.sender];

        if (a.lastCheckInDay == day) revert AlreadyCheckedInToday(msg.sender, day);

        if (!a.registered) {
            a.registered = true;
            uniqueAgents += 1;
            a.registrationOrder = uniqueAgents;
            emit Registered(msg.sender, uniqueAgents);
        }

        // Streak: yesterday -> extend, anything older (or first time) -> restart at 1.
        if (a.totalCheckIns > 0 && a.lastCheckInDay == day - 1) {
            a.currentStreak += 1;
        } else {
            a.currentStreak = 1;
        }
        if (a.currentStreak > a.bestStreak) a.bestStreak = a.currentStreak;

        a.lastCheckInDay = day;
        a.totalCheckIns += 1;
        totalCheckIns += 1;
        _presentOnDay[day] += 1;

        emit CheckedIn(msg.sender, day, a.currentStreak);
    }

    /// @notice Wave at another agent who is present today. Agent ID holders only,
    ///         one wave per (sender, target) pair per UTC day. Purely a social
    ///         counter — waves carry no value and unlock nothing.
    function wave(address to) external {
        if (!isAgent(msg.sender)) revert NotAnAgent(msg.sender);
        if (to == msg.sender) revert CannotWaveYourself();

        uint256 day = currentDay();
        if (_agents[to].lastCheckInDay != day) revert WaveTargetNotPresent(to, day);
        if (_lastWaveDayPlusOne[msg.sender][to] == day + 1) {
            revert AlreadyWavedToday(msg.sender, to, day);
        }

        _lastWaveDayPlusOne[msg.sender][to] = day + 1;
        _agents[to].wavesReceived += 1;

        emit Waved(msg.sender, to, day);
    }
}
