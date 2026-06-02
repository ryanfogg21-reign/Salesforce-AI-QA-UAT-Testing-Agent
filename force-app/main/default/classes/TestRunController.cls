/**
 * TestRunController
 *
 * AuraEnabled Apex for the "Run Script" and "Run Script/s" LWC buttons.
 * Mirrors the logic in RunTestScriptAction but accepts record IDs directly
 * so LWC components on the record page can fire a run without the agent.
 */
public with sharing class TestRunController {

    // ─── Return type ──────────────────────────────────────────────────────────

    public class RunResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String  testRunId;
        @AuraEnabled public String  testRunName;
        @AuraEnabled public String  message;
    }

    // ─── Run a single script by record ID ────────────────────────────────────

    @AuraEnabled
    public static RunResult runScript(Id testScriptId) {
        RunResult result = new RunResult();
        try {
            Test_Script__c script = [
                SELECT Id, Name, Status__c, Test_Suite__c,
                       Target_Org_URL__c, Named_Credential_API_Name__c,
                       Timeout_Minutes__c, Continue_On_Failure__c,
                       Test_Suite__r.Target_Org_URL__c,
                       Test_Suite__r.Named_Credential_API_Name__c
                FROM Test_Script__c
                WHERE Id = :testScriptId
                LIMIT 1
            ];

            if (script.Status__c != 'Active') {
                result.success = false;
                result.message = 'Script "' + script.Name + '" is not Active and cannot be run.';
                return result;
            }

            Integer stepCount = [
                SELECT COUNT()
                FROM Test_Step__c
                WHERE Test_Script__c = :script.Id
                  AND Active__c = true
            ];

            if (stepCount == 0) {
                result.success = false;
                result.message = 'Script "' + script.Name + '" has no active Test Steps.';
                return result;
            }

            Test_Run__c run = new Test_Run__c(
                Test_Script__c  = script.Id,
                Test_Suite__c   = script.Test_Suite__c,
                Status__c       = 'Queued',
                Triggered_By__c = UserInfo.getUserId(),
                Steps_Total__c  = stepCount,
                Steps_Passed__c = 0,
                Steps_Failed__c = 0,
                Session_Id__c   = 'SF-' + String.valueOf(System.now().getTime())
                                + '-' + UserInfo.getUserId().substring(0, 8)
            );
            insert run;

            run = [SELECT Id, Name FROM Test_Run__c WHERE Id = :run.Id];

            String namedCred = String.isNotBlank(script.Named_Credential_API_Name__c)
                ? script.Named_Credential_API_Name__c
                : (script.Test_Suite__r != null && String.isNotBlank(script.Test_Suite__r.Named_Credential_API_Name__c)
                    ? script.Test_Suite__r.Named_Credential_API_Name__c
                    : null);

            String targetUrl = String.isNotBlank(script.Target_Org_URL__c)
                ? script.Target_Org_URL__c
                : (script.Test_Suite__r != null ? script.Test_Suite__r.Target_Org_URL__c : null);

            if (String.isNotBlank(namedCred)) {
                BrowserAgentCallout.executeAsync(run.Id, namedCred, targetUrl);
            }

            result.success     = true;
            result.testRunId   = run.Id;
            result.testRunName = run.Name;
            result.message     = run.Name + ' queued — ' + stepCount + ' step(s) to run.';

        } catch (Exception e) {
            result.success = false;
            result.message = 'Error starting run: ' + e.getMessage();
        }
        return result;
    }

    // ─── Get active scripts for a suite (used by the datatable modal) ─────────

    @AuraEnabled(cacheable=true)
    public static List<Test_Script__c> getScriptsForSuite(Id testSuiteId) {
        return [
            SELECT Id, Name, Priority__c, Last_Run_Status__c, Last_Run_Date__c
            FROM Test_Script__c
            WHERE Test_Suite__c = :testSuiteId
              AND Status__c = 'Active'
            ORDER BY Name ASC
        ];
    }
}
