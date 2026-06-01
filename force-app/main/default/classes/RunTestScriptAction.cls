/**
 * RunTestScriptAction
 *
 * Agentforce Agent Action — called when the QA agent is asked to run a test script.
 * Creates a Test_Run__c record in Queued status and fires an async callout to the
 * browser automation microservice.
 *
 * The agent invokes this by name: "Run UI Test Script"
 */
public with sharing class RunTestScriptAction {

    // ─── Input ────────────────────────────────────────────────────────────────

    public class ActionInput {
        @InvocableVariable(
            label='Test Script Name'
            description='Exact name of the Test Script record to execute'
            required=true
        )
        public String testScriptName;

        @InvocableVariable(
            label='Override Target Org URL'
            description='Optional. Overrides the Target Org URL on the Test Script for this run only.'
            required=false
        )
        public String targetOrgUrlOverride;
    }

    // ─── Output ───────────────────────────────────────────────────────────────

    public class ActionOutput {
        @InvocableVariable(label='Test Run ID')
        public String testRunId;

        @InvocableVariable(label='Test Run Name')
        public String testRunName;

        @InvocableVariable(label='Status Message')
        public String statusMessage;

        @InvocableVariable(label='Success')
        public Boolean success;
    }

    // ─── Invocable Method ─────────────────────────────────────────────────────

    @InvocableMethod(
        label='Run UI Test Script'
        description='Triggers an AI-driven browser automation run for a named Test Script. Returns the Test Run ID to track progress.'
        category='QA Automation'
    )
    public static List<ActionOutput> run(List<ActionInput> inputs) {
        List<ActionOutput> outputs = new List<ActionOutput>();

        for (ActionInput inp : inputs) {
            ActionOutput out = new ActionOutput();

            try {
                // 1. Look up the Test Script by name
                List<Test_Script__c> scripts = [
                    SELECT Id, Name, Status__c, Test_Suite__c,
                           Target_Org_URL__c, Named_Credential_API_Name__c,
                           Timeout_Minutes__c, Continue_On_Failure__c,
                           Run_Script_As__c,
                           Test_Suite__r.Target_Org_URL__c,
                           Test_Suite__r.Named_Credential_API_Name__c,
                           Test_Suite__r.Default_Run_As__c
                    FROM Test_Script__c
                    WHERE Name = :inp.testScriptName
                      AND Status__c = 'Active'
                    LIMIT 1
                ];

                if (scripts.isEmpty()) {
                    out.success = false;
                    out.statusMessage = 'No Active Test Script found with name: ' + inp.testScriptName
                        + '. Please check the name is correct and the script Status is Active.';
                    outputs.add(out);
                    continue;
                }

                Test_Script__c script = scripts[0];

                // 2. Check the script has at least one active step
                Integer stepCount = [
                    SELECT COUNT()
                    FROM Test_Step__c
                    WHERE Test_Script__c = :script.Id
                      AND Active__c = true
                ];

                if (stepCount == 0) {
                    out.success = false;
                    out.statusMessage = 'Test Script "' + script.Name + '" has no active Test Steps. '
                        + 'Please add steps before running.';
                    outputs.add(out);
                    continue;
                }

                // 3. Create the Test Run record
                Test_Run__c run = new Test_Run__c(
                    Test_Script__c     = script.Id,
                    Test_Suite__c      = script.Test_Suite__c,
                    Status__c          = 'Queued',
                    Triggered_By__c    = UserInfo.getUserId(),
                    Steps_Total__c     = stepCount,
                    Steps_Passed__c    = 0,
                    Steps_Failed__c    = 0,
                    Session_Id__c      = generateSessionId()
                );
                insert run;

                // Re-query to get the auto-number Name
                run = [SELECT Id, Name FROM Test_Run__c WHERE Id = :run.Id];

                // 4. Fire async callout (future method to avoid mixed DML / callout limits)
                String namedCred = String.isNotBlank(script.Named_Credential_API_Name__c)
                    ? script.Named_Credential_API_Name__c
                    : (script.Test_Suite__r != null && String.isNotBlank(script.Test_Suite__r.Named_Credential_API_Name__c)
                        ? script.Test_Suite__r.Named_Credential_API_Name__c
                        : null);

                String targetUrl = String.isNotBlank(inp.targetOrgUrlOverride)
                    ? inp.targetOrgUrlOverride
                    : (String.isNotBlank(script.Target_Org_URL__c)
                        ? script.Target_Org_URL__c
                        : (script.Test_Suite__r != null ? script.Test_Suite__r.Target_Org_URL__c : null));

                if (String.isNotBlank(namedCred)) {
                    BrowserAgentCallout.executeAsync(run.Id, namedCred, targetUrl);
                } else {
                    // No service configured yet — mark as queued, service can be wired up later
                    Test_Script__c scriptUpdate = new Test_Script__c(
                        Id = script.Id,
                        Last_Run_Status__c = 'In Progress',
                        Last_Run_Date__c = System.now()
                    );
                    update scriptUpdate;
                }

                out.success      = true;
                out.testRunId    = run.Id;
                out.testRunName  = run.Name;
                out.statusMessage = 'Test run ' + run.Name + ' has been queued for script "'
                    + inp.testScriptName + '" (' + stepCount + ' steps). '
                    + 'I\'ll monitor progress and report back when it completes.';

            } catch (Exception e) {
                out.success = false;
                out.statusMessage = 'Error queuing test run: ' + e.getMessage();
            }

            outputs.add(out);
        }

        return outputs;
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private static String generateSessionId() {
        return 'SF-' + String.valueOf(System.now().getTime())
             + '-' + UserInfo.getUserId().substring(0, 8);
    }
}
