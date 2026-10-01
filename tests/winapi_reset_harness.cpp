// Terminal fake for the MQL function bodies inserted by test_winapi_reset_behavior.py.
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <map>
#include <set>
#include <string>
#include <vector>
using string = std::string;
using ushort = unsigned short;
using uint = unsigned int;
using ulong = unsigned long;
using ENUM_POSITION_TYPE = int;
using ENUM_M4_POSITION_TYPE = int;
const int ACCOUNT_LOGIN=1, TERMINAL_CONNECTED=2, POSITION_MAGIC=3, ORDER_MAGIC=4;
const int POSITION_TYPE_BUY=0, M4_POSITION_TYPE_BUY=0;
const int SYMBOL_VOLUME_MIN=5, SYMBOL_VOLUME_MAX=6, SYMBOL_VOLUME_STEP=7;
const int ENTRY_GRID_ACTIVATION=2, ENTRY_TOTAL_FLOATING_LOSS=3, ENTRY_GRID_SEED_FIRST=4;
const int POSITION_TYPE_SELL=1, M4_POSITION_TYPE_SELL=1;
struct SourceProfile { int grid_initial_max_copies=1; int profile_index=1; double fixed_lot=0.01; int entry_mode=0; };
struct MemorySourcePosition {
    ulong source_id; string symbol="XAUUSD"; int position_type=0;
    double volume=0.01, sl=0, tp=0;
    string comment=""; long magic=0;
};
struct Exposure { ulong magic; bool mapped=false; };
std::vector<Exposure> positions, orders;
int position_index=0, order_index=0;
std::map<string,double> globals;
std::set<string> failed_deletes, failed_sets;
bool fail_all_sets=false, connected=true, fresh=true, fail_second_read=false;
bool g_reset_blocked=false, g_reset_waiting_snapshot=false, g_panel_entries_paused=false;
bool g_round_copy_tracking_ready=true;
ulong g_snapshot_sequence=17, g_reset_snapshot_sequence=0;
ulong InpCopyMagic=123;
string InpChannelName="channel", g_prefix="WMLFC_TEST_", g_panel_last_action;
std::vector<string> g_round_copy_keys={"old"};
std::vector<int> g_round_copy_counts={1}, g_missing_source_confirmations={1};
std::vector<MemorySourcePosition> g_sources;
int g_last_first_entry_time_filter_log=9, read_calls=0, flushes=0;
bool baseline_was_empty=false;
std::vector<ulong> attempts, opened;
std::set<ulong> failed_orders;
bool InpCloseCopyWithSource=true, fail_grid_check=false;
int entry_checks=0, close_checks=0, total_checks=0;
string IntegerToString(long value) { return std::to_string(value); }
int StringLen(const string& s) { return int(s.size()); }
int StringFind(const string& s,const string& part) { auto p=s.find(part); return p==string::npos ? -1 : int(p); }
string StringSubstr(const string& s,int start,int size=-1) { return s.substr(start,size<0?string::npos:size); }
ushort StringGetCharacter(const string& s,int i) { return (unsigned char)s.at(i); }
long AccountInfoInteger(int) { return 100; }
bool TerminalInfoInteger(int) { return connected; }
long TimeCurrent() { return 123456; }
template<class... T> void Print(T...) {}
template<class... T> void PrintFormat(T...) {}
template<class T> int ArraySize(const std::vector<T>& v) { return int(v.size()); }
template<class T> void ArrayResize(std::vector<T>& v,int n) { v.resize(n); }
bool GlobalVariableCheck(const string& s) { return globals.count(s); }
double GlobalVariableGet(const string& s) { return globals.at(s); }
long GlobalVariableSet(const string& s,double v) {
    if(fail_all_sets || failed_sets.count(s)) return 0;
    globals[s]=v; return TimeCurrent();
}
bool GlobalVariableDel(const string& s) {
    if(failed_deletes.count(s)) return false;
    return globals.erase(s)>0;
}
int GlobalVariablesTotal() { return int(globals.size()); }
string GlobalVariableName(int n) { auto i=globals.begin(); std::advance(i,n); return i->first; }
void GlobalVariablesFlush() { flushes++; }
int PositionsTotal() { return int(positions.size()); }
ulong PositionGetTicket(int i) { position_index=i; return i+1; }
bool PositionSelectByTicket(ulong i) { position_index=int(i)-1; return i>0 && i<=positions.size(); }
ulong PositionGetInteger(int) { return positions.at(position_index).magic; }
bool IsCopyPosition() { return positions.at(position_index).mapped; }
int OrdersTotal() { return int(orders.size()); }
ulong OrderGetTicket(int i) { order_index=i; return i+1; }
bool OrderSelect(ulong i) { order_index=int(i)-1; return i>0 && i<=orders.size(); }
ulong OrderGetInteger(int) { return orders.at(order_index).magic; }
void M4InvalidateTradeCache() {}
#define M4PositionsTotal PositionsTotal
#define M4PositionGetTicket PositionGetTicket
#define M4PositionSelectByTicket PositionSelectByTicket
#define M4PositionGetInteger PositionGetInteger
#define M4_POSITION_MAGIC POSITION_MAGIC
#define M4PendingOrdersTotal OrdersTotal
#define M4PendingOrderGetTicket OrderGetTicket
#define M4PendingOrderSelectByTicket OrderSelect
#define M4PendingOrderGetInteger OrderGetInteger
#define M4_ORDER_MAGIC ORDER_MAGIC
bool LoadMemorySnapshot(bool) { read_calls++; return fresh && !(fail_second_read && read_calls==2); }
void UpdateRoundCopyTracking() {
    baseline_was_empty=g_round_copy_keys.empty() && g_round_copy_counts.empty() && !g_round_copy_tracking_ready;
    g_round_copy_tracking_ready=true;
}
string CopyGlobalName(ulong,int);
bool IsAlreadyCopied(ulong id,int level) { return GlobalVariableCheck(CopyGlobalName(id,level)); }
bool IsSourcePositionForProfile(const SourceProfile&,const MemorySourcePosition&) { return true; }
double CalculateCopyVolume(const string&,double v,const SourceProfile&,int) { return v; }
double PartialRetryVolume(const string&,ulong,int,double v) { return v; }
double LevelFixedLot(const SourceProfile& p,int) { return p.fixed_lot; }
double SymbolInfoDouble(const string&,int) { return 0.01; }
bool IsFirstCopyEntryTimeBlocked() { return false; }
template<class... T> void LogFirstEntryTimeFilterSkip(T...) {}
bool OpenCopyTrade(ulong id,const string&,int,double,double,double,double,double,const SourceProfile&,int) {
    attempts.push_back(id);
    if(failed_orders.count(id)) return false;
    opened.push_back(id); positions.push_back({InpCopyMagic,true}); return true;
}
void PanelUpdate(bool) {}
void CloseCopiesWithoutSource() {}
void DeletePendingsWithoutSource() {}
void CleanupFinishedCopyState() {}
void ResetInactiveGridGroups() {}
void ResetInactiveGridSeedSources() {}
void ResetInactiveTotalLossGroups() {}
void CheckMinuteProfitClose() { close_checks++; }
void CheckBasketProfitClose() {}
void ApplyFirstEntryTimeFilter() {}
bool PanelEntriesPaused() { return g_panel_entries_paused; }
void CheckGridActivationEntries() { if(fail_grid_check) g_reset_blocked=true; }
void CheckTotalLossActivationEntries() { total_checks++; }
bool MatchSourceProfile(const string&,long,const string&,SourceProfile&) { return true; }
void ProcessSourceLevel(const MemorySourcePosition&,const SourceProfile&,int) { entry_checks++; }

// EA_FUNCTIONS

int main(int argc,char** argv) {
    assert(argc==2); string scenario=argv[1];
    const string copied=CopyGlobalName(41,1);
    const string stopped=GridGroupStateName("S",1,"XAUUSD",0);
    const string active=GridGroupStateName("A",1,"XAUUSD",0);
    const string total=TotalLossGroupStateName("A",1,"XAUUSD");
    const string decision=GridInitialSourceName(42);
    const string block=ResetBlockGlobalName();
    globals[copied]=1; globals[stopped]=1; globals[active]=1;
    globals[total]=1; globals[decision]=0; globals["UNRELATED"]=3;
#ifdef MQ5
    globals[g_prefix+"PARTIAL_43_L1"]=0.02;
    globals[GridSeedStatePrefix()+"1_0_XAUUSD"]=41;
#endif
    if(scenario=="reset" || scenario=="paused") {
        g_panel_entries_paused=scenario=="paused";
        PanelResetFollowing();
        assert(globals.size()==1 && globals.count("UNRELATED"));
        assert(!g_reset_blocked && g_reset_waiting_snapshot && g_reset_snapshot_sequence==17);
        assert(g_panel_entries_paused==(scenario=="paused"));
        assert(baseline_was_empty && g_missing_source_confirmations.empty());
        assert(flushes>=3 && attempts.empty());
        PanelResetFollowing(); assert(!g_reset_blocked && globals.size()==1);
    } else if(scenario=="stale" || scenario=="disconnected") {
        auto before=globals;
        fresh=scenario!="stale"; connected=scenario!="disconnected";
        PanelResetFollowing(); assert(globals==before && !g_reset_waiting_snapshot);
    } else if(scenario=="exposure") {
        auto before=globals;
        positions={{InpCopyMagic,false}}; PanelResetFollowing(); assert(globals==before);
        positions={{0,true}}; PanelResetFollowing(); assert(globals==before);
        positions.clear(); orders={{InpCopyMagic,false}};
        PanelResetFollowing(); assert(globals==before);
        orders={{999,false}}; positions={{999,false}};
        PanelResetFollowing(); assert(!globals.count(copied) && !g_reset_blocked);
    } else if(scenario=="scope") {
        string other_copy,other_grid,other_total;
#ifdef MQ4
        InpCopyMagic=1234;
#else
        string own_prefix=g_prefix; g_prefix="OTHER_RECEIVER_";
#endif
        other_copy=CopyGlobalName(41,1); other_grid=GridGroupStateName("S",1,"XAUUSD",0);
        other_total=TotalLossGroupStateName("A",1,"XAUUSD");
#ifdef MQ4
        InpCopyMagic=123;
#else
        g_prefix=own_prefix;
#endif
        globals[other_copy]=1; globals[other_grid]=1; globals[other_total]=1;
        const string mapping=g_prefix+"P_SRC_123_888";
        globals[mapping]=41; globals[copied+"_OTHER"]=1;
        PanelResetFollowing();
        assert(globals.count(other_copy) && globals.count(other_grid) && globals.count(other_total));
        assert(globals.count(mapping) && globals.count(copied+"_OTHER") && !globals.count(copied));
    } else if(scenario=="delete_failure" || scenario=="unlock_failure") {
        failed_deletes.insert(scenario=="delete_failure"?copied:block);
        PanelResetFollowing(); assert(g_reset_blocked && globals.count(block));
        // This is also the OnInit recovery condition after a terminal/EA restart.
        g_reset_blocked=GlobalVariableCheck(ResetBlockGlobalName()); assert(g_reset_blocked);
        failed_deletes.clear(); PanelResetFollowing();
        assert(!g_reset_blocked && !globals.count(copied) && !globals.count(block));
    } else if(scenario=="lock_failure") {
        auto before=globals; failed_sets.insert(block); PanelResetFollowing();
        assert(globals==before && g_reset_blocked);
    } else if(scenario=="recheck_failure") {
        fail_second_read=true; PanelResetFollowing();
        assert(g_reset_blocked && globals.count(block) && attempts.empty());
    } else if(scenario=="entry_gates") {
        g_sources.push_back({41}); PanelResetFollowing();
        CheckPositions(); assert(entry_checks==0 && total_checks==0 && close_checks==1);
        g_snapshot_sequence++; fresh=false;
        CheckPositions(); assert(entry_checks==0 && g_reset_waiting_snapshot);
        fresh=true; CheckPositions(); assert(entry_checks==3 && !g_reset_waiting_snapshot);
        g_panel_entries_paused=true; CheckPositions(); assert(entry_checks==3);
        g_panel_entries_paused=false; g_reset_blocked=true;
        CheckPositions(); assert(entry_checks==3);
        g_reset_blocked=false; fail_grid_check=true; total_checks=0;
        CheckPositions(); assert(entry_checks==3 && total_checks==0 && g_reset_blocked);
    } else {
        globals.clear(); SourceProfile profile;
        for(ulong id=1;id<=4;id++) g_sources.push_back({id});
        g_sources.push_back({90,"EURUSD",0}); g_sources.push_back({91,"XAUUSD",1});
        if(scenario=="grid_unlimited") profile.grid_initial_max_copies=0;
        if(scenario=="grid_write_failure") failed_sets.insert(GridInitialSourceName(3));
        bool prepared=PrepareGridInitialSources(profile,"XAUUSD",0);
        if(scenario=="grid_write_failure") {
            assert(!prepared && g_reset_blocked && globals.count(block) && attempts.empty());
        } else {
            assert(prepared);
            if(scenario=="grid_retry") failed_orders.insert(4);
            CopyGridSources(profile,"XAUUSD","XAUUSD",0,3,3);
            if(scenario=="grid_retry") {
                assert(opened.empty() && attempts==std::vector<ulong>{4});
                // A retry/reinitialization must not widen the reserved initial set.
                assert(PrepareGridInitialSources(profile,"XAUUSD",0));
                CopyGridSources(profile,"XAUUSD","XAUUSD",0,3,3);
                assert(opened.empty() && attempts==std::vector<ulong>({4,4}));
                failed_orders.clear(); CopyGridSources(profile,"XAUUSD","XAUUSD",0,3,3);
            }
            const int expected=scenario=="grid_unlimited"?4:1;
            assert(int(opened.size())==expected);
            CopyGridSources(profile,"XAUUSD","XAUUSD",0,3,3);
            assert(int(opened.size())==expected);
            g_sources.push_back({5}); CopyGridSources(profile,"XAUUSD","XAUUSD",0,3,3);
            assert(int(opened.size())==expected+1 && opened.back()==5);
            assert(!globals.count(GridInitialSourceName(90)) && !globals.count(GridInitialSourceName(91)));
            positions.clear(); PanelResetFollowing(); assert(!g_reset_blocked);
            assert(PrepareGridInitialSources(profile,"XAUUSD",0));
            assert(!IsGridInitialSourceSkipped(5));
        }
    }
    std::cout<<scenario<<" passed\n";
}
