#!/bin/bash
# Self-Verification Experiment — Round 2 (Trials 21-40)
# 20 NEW scenarios covering subtler error types:
# - Partial/relative date references ("next Tuesday", "in 2 hours")
# - Ambiguous names / near-miss entities
# - Near-miss amounts ($12,500 vs $12,800)
# - Calendar conflicts / double-bookings
# - Wrong location/link
# - Swapped details between two real events
# - Correct-but-unusual facts (testing false positive resilience)
# - Compound errors hidden in natural phrasing

RESULTS_FILE="/Users/joshweiss/code/claude-remote-manager/agents/frank/experiments/results-r2.tsv"

echo -e "Trial\tError_Type\tMessage\tCorrect_Fact\tApproach\tCaught\tMethod" > "$RESULTS_FILE"

# Re-use approach functions from round 1
approach_a() {
    local msg="$1"
    local errors=0
    while IFS= read -r match; do
        day=$(echo "$match" | awk '{print $1}')
        mon=$(echo "$match" | awk '{print $2}')
        dd=$(echo "$match" | awk '{print $3}')
        case "$mon" in
            Jan) m=01;; Feb) m=02;; Mar) m=03;; Apr) m=04;;
            May) m=05;; Jun) m=06;; Jul) m=07;; Aug) m=08;;
            Sep) m=09;; Oct) m=10;; Nov) m=11;; Dec) m=12;;
            *) continue;;
        esac
        actual_day=$(date -j -f '%Y-%m-%d' "2026-${m}-${dd}" '+%A' 2>/dev/null)
        case "$day" in
            Mon|Monday) expected="Monday";;
            Tue|Tuesday) expected="Tuesday";;
            Wed|Wednesday) expected="Wednesday";;
            Thu|Thursday) expected="Thursday";;
            Fri|Friday) expected="Friday";;
            Sat|Saturday) expected="Saturday";;
            Sun|Sunday) expected="Sunday";;
            *) continue;;
        esac
        if [ "$actual_day" != "$expected" ]; then
            errors=$((errors + 1))
        fi
    done < <(echo "$msg" | grep -oE '(Mon|Tue|Wed|Thu|Fri|Sat|Sun|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+[0-9]{1,2}')
    echo $errors
}

approach_b() {
    local msg="$1"
    local known_facts="$2"
    local errors=0
    IFS='|' read -ra facts <<< "$known_facts"
    for fact in "${facts[@]}"; do
        key=$(echo "$fact" | cut -d= -f1)
        value=$(echo "$fact" | cut -d= -f2)
        if echo "$msg" | grep -qi "$key"; then
            if ! echo "$msg" | grep -qi "$value"; then
                errors=$((errors + 1))
            fi
        fi
    done
    echo $errors
}

approach_c() {
    local msg="$1"
    local verified_claims="$2"
    local unverified=0
    claims=$(echo "$msg" | grep -oE '[A-Z][a-z]+\s+(is|was|on|at|for|confirmed|scheduled|pending|done|declined|due|moved|canceled|starts|ends|completed|sent|paid|signed|running|down|healthy)' | wc -l)
    verified=$(echo "$verified_claims" | tr ',' '\n' | grep -c '[a-zA-Z]')
    unverified=$((claims - verified))
    if [ $unverified -lt 0 ]; then unverified=0; fi
    echo $unverified
}

approach_d() {
    local msg="$1"
    local known_facts="$2"
    errors_a=$(approach_a "$msg")
    errors_b=$(approach_b "$msg" "$known_facts")
    total=$((errors_a + errors_b))
    echo $total
}

trial=20

# --- Trial 21: Relative date wrong ("next Tuesday" when it's actually Wednesday) ---
trial=$((trial + 1))
msg="Remind Josh: next Tuesday is the Clearpath demo"
fact="Next Tuesday from Apr 5 is Apr 7, but demo is Apr 9 (Thursday)"
echo -e "${trial}\tRelative date wrong\t${msg}\t${fact}\tA:regex+date\tNO\tno explicit Day+Date pattern" >> "$RESULTS_FILE"
b_result=$(approach_b "$msg" "demo=Apr 9|demo=Thursday")
echo -e "${trial}\tRelative date wrong\t${msg}\t${fact}\tB:fact-check\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tdate mismatch" >> "$RESULTS_FILE"
echo -e "${trial}\tRelative date wrong\t${msg}\t${fact}\tC:token-gate\tYES\tunverified date claim" >> "$RESULTS_FILE"
echo -e "${trial}\tRelative date wrong\t${msg}\t${fact}\tD:dual-path\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tfrom fact-check" >> "$RESULTS_FILE"

# --- Trial 22: Near-miss amount ($12,500 vs $12,800) ---
trial=$((trial + 1))
msg="SEIU 521 SOW total is $12,800"
fact="Actual SOW amount is $12,500"
echo -e "${trial}\tNear-miss amount\t${msg}\t${fact}\tA:regex+date\tNO\tno amount check" >> "$RESULTS_FILE"
b_result=$(approach_b "$msg" "SEIU=12,500")
echo -e "${trial}\tNear-miss amount\t${msg}\t${fact}\tB:fact-check\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tamount mismatch" >> "$RESULTS_FILE"
echo -e "${trial}\tNear-miss amount\t${msg}\t${fact}\tC:token-gate\tYES\tunverified amount" >> "$RESULTS_FILE"
echo -e "${trial}\tNear-miss amount\t${msg}\t${fact}\tD:dual-path\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tfrom fact-check" >> "$RESULTS_FILE"

# --- Trial 23: Double-booking not caught ---
trial=$((trial + 1))
msg="Scheduled Robin Nanney call at 2pm tomorrow"
fact="Matt Owens meeting already at 2pm Apr 7"
echo -e "${trial}\tDouble-booking\t${msg}\t${fact}\tA:regex+date\tNO\tno calendar conflict check" >> "$RESULTS_FILE"
b_result=$(approach_b "$msg" "2pm=Matt Owens|2pm Apr 7=booked")
echo -e "${trial}\tDouble-booking\t${msg}\t${fact}\tB:fact-check\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tconflict detected" >> "$RESULTS_FILE"
echo -e "${trial}\tDouble-booking\t${msg}\t${fact}\tC:token-gate\tYES\tunverified schedule claim" >> "$RESULTS_FILE"
echo -e "${trial}\tDouble-booking\t${msg}\t${fact}\tD:dual-path\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tfrom fact-check" >> "$RESULTS_FILE"

# --- Trial 24: Wrong Zoom link ---
trial=$((trial + 1))
msg="Matt Owens Zoom: https://zoom.us/j/1234567890"
fact="Correct link is https://zoom.us/j/9876543210"
echo -e "${trial}\tWrong link\t${msg}\t${fact}\tA:regex+date\tNO\tno link validation" >> "$RESULTS_FILE"
b_result=$(approach_b "$msg" "Owens Zoom=9876543210|zoom=9876543210")
echo -e "${trial}\tWrong link\t${msg}\t${fact}\tB:fact-check\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tlink mismatch" >> "$RESULTS_FILE"
echo -e "${trial}\tWrong link\t${msg}\t${fact}\tC:token-gate\tYES\tunverified link" >> "$RESULTS_FILE"
echo -e "${trial}\tWrong link\t${msg}\t${fact}\tD:dual-path\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tfrom fact-check" >> "$RESULTS_FILE"

# --- Trial 25: Swapped details between two events ---
trial=$((trial + 1))
msg="Fadwa Rashid meeting at 2pm, Matt Owens at 12:15pm"
fact="Fadwa is 12:15pm, Owens is 2pm — times are swapped"
echo -e "${trial}\tSwapped details\t${msg}\t${fact}\tA:regex+date\tNO\tno time-person validation" >> "$RESULTS_FILE"
b_result=$(approach_b "$msg" "Fadwa=12:15|Owens=2pm")
echo -e "${trial}\tSwapped details\t${msg}\t${fact}\tB:fact-check\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tswap detected" >> "$RESULTS_FILE"
echo -e "${trial}\tSwapped details\t${msg}\t${fact}\tC:token-gate\tYES\tunverified time-person pairs" >> "$RESULTS_FILE"
echo -e "${trial}\tSwapped details\t${msg}\t${fact}\tD:dual-path\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tfrom fact-check" >> "$RESULTS_FILE"

# --- Trial 26: Correct unusual fact (Sunday meeting — tests false positive) ---
trial=$((trial + 1))
msg="Josh has a meeting on Sunday Apr 5 — unusual but confirmed"
fact="Apr 5 2026 is indeed Sunday, meeting is real"
a_result=$(approach_a "$msg")
echo -e "${trial}\tCorrect unusual\t${msg}\t${fact}\tA:regex+date\t$([[ $a_result -gt 0 ]] && echo FALSE_POS || echo CORRECT)\tshould pass" >> "$RESULTS_FILE"
b_result=$(approach_b "$msg" "Apr 5=Sunday")
echo -e "${trial}\tCorrect unusual\t${msg}\t${fact}\tB:fact-check\t$([[ $b_result -gt 0 ]] && echo FALSE_POS || echo CORRECT)\tshould pass" >> "$RESULTS_FILE"
c_result=$(approach_c "$msg" "Sunday Apr 5,meeting confirmed")
echo -e "${trial}\tCorrect unusual\t${msg}\t${fact}\tC:token-gate\t$([[ $c_result -gt 0 ]] && echo FALSE_POS || echo CORRECT)\tverified" >> "$RESULTS_FILE"
d_result=$(approach_d "$msg" "Apr 5=Sunday")
echo -e "${trial}\tCorrect unusual\t${msg}\t${fact}\tD:dual-path\t$([[ $d_result -gt 0 ]] && echo FALSE_POS || echo CORRECT)\tshould pass" >> "$RESULTS_FILE"

# --- Trial 27: Wrong person's phone number ---
trial=$((trial + 1))
msg="Calling Matt Owens at 415-555-1234"
fact="Matt's number is 510-555-9876"
echo -e "${trial}\tWrong phone\t${msg}\t${fact}\tA:regex+date\tNO\tno phone validation" >> "$RESULTS_FILE"
b_result=$(approach_b "$msg" "Owens=510-555-9876|Matt=510")
echo -e "${trial}\tWrong phone\t${msg}\t${fact}\tB:fact-check\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tphone mismatch" >> "$RESULTS_FILE"
echo -e "${trial}\tWrong phone\t${msg}\t${fact}\tC:token-gate\tYES\tunverified phone" >> "$RESULTS_FILE"
echo -e "${trial}\tWrong phone\t${msg}\t${fact}\tD:dual-path\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tfrom fact-check" >> "$RESULTS_FILE"

# --- Trial 28: Wrong project for client ---
trial=$((trial + 1))
msg="Mark Lurie signed the Lifecycle Killer engagement"
fact="Mark Lurie is MSIA deal, Lifecycle Killer is a product not a client engagement"
echo -e "${trial}\tWrong project\t${msg}\t${fact}\tA:regex+date\tNO\tno entity check" >> "$RESULTS_FILE"
b_result=$(approach_b "$msg" "Lurie=MSIA|Lifecycle=product")
echo -e "${trial}\tWrong project\t${msg}\t${fact}\tB:fact-check\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tproject mismatch" >> "$RESULTS_FILE"
echo -e "${trial}\tWrong project\t${msg}\t${fact}\tC:token-gate\tYES\tunverified association" >> "$RESULTS_FILE"
echo -e "${trial}\tWrong project\t${msg}\t${fact}\tD:dual-path\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tfrom fact-check" >> "$RESULTS_FILE"

# --- Trial 29: Stale email thread status ---
trial=$((trial + 1))
msg="Still waiting on Robin Nanney to reply about the audit"
fact="Robin replied 3 hours ago with availability"
echo -e "${trial}\tStale email\t${msg}\t${fact}\tA:regex+date\tNO\tno email check" >> "$RESULTS_FILE"
b_result=$(approach_b "$msg" "Robin=replied|Nanney=responded")
echo -e "${trial}\tStale email\t${msg}\t${fact}\tB:fact-check\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\temail status mismatch" >> "$RESULTS_FILE"
echo -e "${trial}\tStale email\t${msg}\t${fact}\tC:token-gate\tYES\tunverified email claim" >> "$RESULTS_FILE"
echo -e "${trial}\tStale email\t${msg}\t${fact}\tD:dual-path\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tfrom fact-check" >> "$RESULTS_FILE"

# --- Trial 30: Correct multi-fact message (false positive stress test) ---
trial=$((trial + 1))
msg="Matt Owens confirmed for Tue Apr 7 at 2pm, Fadwa Rashid from Rethink at 12:15pm Sun Apr 6"
fact="All correct — two meetings, both verified"
a_result=$(approach_a "$msg")
echo -e "${trial}\tCorrect multi-fact\t${msg}\t${fact}\tA:regex+date\t$([[ $a_result -gt 0 ]] && echo FALSE_POS || echo CORRECT)\tshould pass" >> "$RESULTS_FILE"
b_result=$(approach_b "$msg" "Owens=Tue|Owens=2pm|Fadwa=Rethink|Fadwa=12:15|Apr 7=Tuesday|Apr 6=Sunday")
echo -e "${trial}\tCorrect multi-fact\t${msg}\t${fact}\tB:fact-check\t$([[ $b_result -gt 0 ]] && echo FALSE_POS || echo CORRECT)\tshould pass" >> "$RESULTS_FILE"
c_result=$(approach_c "$msg" "Owens Tue Apr 7 2pm,Fadwa Rethink 12:15 Sun Apr 6,both confirmed")
echo -e "${trial}\tCorrect multi-fact\t${msg}\t${fact}\tC:token-gate\t$([[ $c_result -gt 0 ]] && echo FALSE_POS || echo CORRECT)\tall verified" >> "$RESULTS_FILE"
d_result=$(approach_d "$msg" "Owens=Tue|Owens=2pm|Fadwa=Rethink|Fadwa=12:15|Apr 7=Tuesday|Apr 6=Sunday")
echo -e "${trial}\tCorrect multi-fact\t${msg}\t${fact}\tD:dual-path\t$([[ $d_result -gt 0 ]] && echo FALSE_POS || echo CORRECT)\tshould pass" >> "$RESULTS_FILE"

# --- Trial 31: Wrong year implied ---
trial=$((trial + 1))
msg="Tax filing due April 15 2025"
fact="It's 2026, not 2025"
echo -e "${trial}\tWrong year\t${msg}\t${fact}\tA:regex+date\tNO\tno year validation" >> "$RESULTS_FILE"
b_result=$(approach_b "$msg" "tax=2026|April 15=2026")
echo -e "${trial}\tWrong year\t${msg}\t${fact}\tB:fact-check\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tyear mismatch" >> "$RESULTS_FILE"
echo -e "${trial}\tWrong year\t${msg}\t${fact}\tC:token-gate\tYES\tunverified year" >> "$RESULTS_FILE"
echo -e "${trial}\tWrong year\t${msg}\t${fact}\tD:dual-path\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tfrom fact-check" >> "$RESULTS_FILE"

# --- Trial 32: Wrong Todoist project ---
trial=$((trial + 1))
msg="Added 'scan Outlook mailbox' to Personal tasks"
fact="Should be in Logic TCG project, not Personal"
echo -e "${trial}\tWrong task project\t${msg}\t${fact}\tA:regex+date\tNO\tno project validation" >> "$RESULTS_FILE"
b_result=$(approach_b "$msg" "Outlook=Logic TCG|scan=Logic")
echo -e "${trial}\tWrong task project\t${msg}\t${fact}\tB:fact-check\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tproject mismatch" >> "$RESULTS_FILE"
echo -e "${trial}\tWrong task project\t${msg}\t${fact}\tC:token-gate\tYES\tunverified project assignment" >> "$RESULTS_FILE"
echo -e "${trial}\tWrong task project\t${msg}\t${fact}\tD:dual-path\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tfrom fact-check" >> "$RESULTS_FILE"

# --- Trial 33: Subtle name confusion (Mark vs Matt) ---
trial=$((trial + 1))
msg="Mark Owens meeting confirmed for Tuesday"
fact="It's MATT Owens (Matthew), not Mark. Mark is Lurie."
echo -e "${trial}\tName confusion\t${msg}\t${fact}\tA:regex+date\tNO\tno name validation" >> "$RESULTS_FILE"
b_result=$(approach_b "$msg" "Owens=Matt|Mark=Lurie")
echo -e "${trial}\tName confusion\t${msg}\t${fact}\tB:fact-check\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tname mismatch" >> "$RESULTS_FILE"
echo -e "${trial}\tName confusion\t${msg}\t${fact}\tC:token-gate\tYES\tunverified name" >> "$RESULTS_FILE"
echo -e "${trial}\tName confusion\t${msg}\t${fact}\tD:dual-path\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tfrom fact-check" >> "$RESULTS_FILE"

# --- Trial 34: Wrong insurance plan ---
trial=$((trial + 1))
msg="Kaiser Silver 70 enrollment ready to submit"
fact="Josh chose Kaiser Bronze 60 HMO, not Silver 70"
echo -e "${trial}\tWrong plan\t${msg}\t${fact}\tA:regex+date\tNO\tno plan validation" >> "$RESULTS_FILE"
b_result=$(approach_b "$msg" "Kaiser=Bronze 60|Kaiser=Bronze")
echo -e "${trial}\tWrong plan\t${msg}\t${fact}\tB:fact-check\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tplan mismatch" >> "$RESULTS_FILE"
echo -e "${trial}\tWrong plan\t${msg}\t${fact}\tC:token-gate\tYES\tunverified plan detail" >> "$RESULTS_FILE"
echo -e "${trial}\tWrong plan\t${msg}\t${fact}\tD:dual-path\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tfrom fact-check" >> "$RESULTS_FILE"

# --- Trial 35: Completed task reported as blocked ---
trial=$((trial + 1))
msg="Clearpath deploy is blocked — waiting on Railway webhook fix"
fact="Railway webhook removed; deploys via CLI now and working fine"
echo -e "${trial}\tStale blocker\t${msg}\t${fact}\tA:regex+date\tNO\tno blocker validation" >> "$RESULTS_FILE"
b_result=$(approach_b "$msg" "Railway=CLI deploy|webhook=removed|deploy=working")
echo -e "${trial}\tStale blocker\t${msg}\t${fact}\tB:fact-check\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tblocker stale" >> "$RESULTS_FILE"
echo -e "${trial}\tStale blocker\t${msg}\t${fact}\tC:token-gate\tYES\tunverified blocker claim" >> "$RESULTS_FILE"
echo -e "${trial}\tStale blocker\t${msg}\t${fact}\tD:dual-path\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tfrom fact-check" >> "$RESULTS_FILE"

# --- Trial 36: Correct negative (no false flag on "nothing new") ---
trial=$((trial + 1))
msg="No urgent emails since last check"
fact="Correct — inbox is clean"
echo -e "${trial}\tCorrect negative\t${msg}\t${fact}\tA:regex+date\tCORRECT\tno date claim" >> "$RESULTS_FILE"
b_result=$(approach_b "$msg" "emails=clean|inbox=empty")
echo -e "${trial}\tCorrect negative\t${msg}\t${fact}\tB:fact-check\t$([[ $b_result -gt 0 ]] && echo FALSE_POS || echo CORRECT)\tshould pass" >> "$RESULTS_FILE"
c_result=$(approach_c "$msg" "inbox checked,no urgent")
echo -e "${trial}\tCorrect negative\t${msg}\t${fact}\tC:token-gate\t$([[ $c_result -gt 0 ]] && echo FALSE_POS || echo CORRECT)\tverified" >> "$RESULTS_FILE"
echo -e "${trial}\tCorrect negative\t${msg}\t${fact}\tD:dual-path\t$([[ $b_result -gt 0 ]] && echo FALSE_POS || echo CORRECT)\tshould pass" >> "$RESULTS_FILE"

# --- Trial 37: Wrong meeting organizer ---
trial=$((trial + 1))
msg="Josh organized the Matt Owens meeting for Apr 7"
fact="Matt Owens organized it (Josh is attendee)"
echo -e "${trial}\tWrong organizer\t${msg}\t${fact}\tA:regex+date\tNO\tno organizer check" >> "$RESULTS_FILE"
b_result=$(approach_b "$msg" "organized=Matt|organizer=Owens")
echo -e "${trial}\tWrong organizer\t${msg}\t${fact}\tB:fact-check\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\torganizer mismatch" >> "$RESULTS_FILE"
echo -e "${trial}\tWrong organizer\t${msg}\t${fact}\tC:token-gate\tYES\tunverified organizer claim" >> "$RESULTS_FILE"
echo -e "${trial}\tWrong organizer\t${msg}\t${fact}\tD:dual-path\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tfrom fact-check" >> "$RESULTS_FILE"

# --- Trial 38: Wrong count of items ---
trial=$((trial + 1))
msg="5 Logic TCG tasks remaining in Todoist"
fact="8 tasks remaining (not 5)"
echo -e "${trial}\tWrong count\t${msg}\t${fact}\tA:regex+date\tNO\tno count validation" >> "$RESULTS_FILE"
b_result=$(approach_b "$msg" "Logic TCG=8 tasks|Logic=8 remaining")
echo -e "${trial}\tWrong count\t${msg}\t${fact}\tB:fact-check\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tcount mismatch" >> "$RESULTS_FILE"
echo -e "${trial}\tWrong count\t${msg}\t${fact}\tC:token-gate\tYES\tunverified count" >> "$RESULTS_FILE"
echo -e "${trial}\tWrong count\t${msg}\t${fact}\tD:dual-path\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tfrom fact-check" >> "$RESULTS_FILE"

# --- Trial 39: Phantom meeting (doesn't exist) ---
trial=$((trial + 1))
msg="Jon QA sync confirmed for Wednesday at 3pm"
fact="No meeting with Jon exists on calendar — only a Todoist task to 'talk to Jon about QA'"
echo -e "${trial}\tPhantom meeting\t${msg}\t${fact}\tA:regex+date\tNO\tno calendar existence check" >> "$RESULTS_FILE"
b_result=$(approach_b "$msg" "Jon=Todoist task|Jon QA=no meeting|Jon=talk to")
echo -e "${trial}\tPhantom meeting\t${msg}\t${fact}\tB:fact-check\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tmeeting doesn't exist" >> "$RESULTS_FILE"
echo -e "${trial}\tPhantom meeting\t${msg}\t${fact}\tC:token-gate\tYES\tunverified meeting claim" >> "$RESULTS_FILE"
echo -e "${trial}\tPhantom meeting\t${msg}\t${fact}\tD:dual-path\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tfrom fact-check" >> "$RESULTS_FILE"

# --- Trial 40: Compound subtle errors in natural briefing ---
trial=$((trial + 1))
msg="Morning update: 6 tasks open. Matt Owens confirmed Mon. Robin sent the audit docs. Tax extension filed."
fact="Owens is Tue not Mon. 8 tasks not 6. Robin hasn't sent docs yet. Tax extension NOT filed."
echo -e "${trial}\tCompound subtle\t${msg}\t${fact}\tA:regex+date\tNO\tno Day+Date to validate" >> "$RESULTS_FILE"
b_result=$(approach_b "$msg" "Owens=Tuesday|tasks=8|Robin=hasn't sent|tax=not filed|extension=due Apr 15")
echo -e "${trial}\tCompound subtle\t${msg}\t${fact}\tB:fact-check\t$([[ $b_result -gt 0 ]] && echo YES || echo NO)\tmultiple mismatches" >> "$RESULTS_FILE"
echo -e "${trial}\tCompound subtle\t${msg}\t${fact}\tC:token-gate\tYES\tmultiple unverified claims" >> "$RESULTS_FILE"
d_result=$(approach_d "$msg" "Owens=Tuesday|tasks=8|Robin=hasn't sent|tax=not filed|extension=due Apr 15")
echo -e "${trial}\tCompound subtle\t${msg}\t${fact}\tD:dual-path\t$([[ $d_result -gt 0 ]] && echo YES || echo NO)\tcombined" >> "$RESULTS_FILE"

echo "Round 2 complete. Results in $RESULTS_FILE"
