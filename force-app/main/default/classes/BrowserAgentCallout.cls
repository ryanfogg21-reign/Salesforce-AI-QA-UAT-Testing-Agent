/**
 * BrowserAgentCallout
 *
 * Fires HTTP callouts to the browser automation microservice.
 * Called asynchronously from RunTestScriptAction to stay within
 * Salesforce governor limits (no mixed DML + callout in same transaction).
 *
 * When the microservice completes a run, it POSTs the result to the
 * REST callback endpoint defined in TestRunCallbackResource.
 */
public with sharing class BrowserAgentCallout {

    // ─── Async Trigger (called from InvocableMethod) ──────────────────────────

    @future(callout=true)
    public static void executeAsync(Id testRunId, String namedCredential, String targetUrl) {
        try {
            // Gather everything needed for the request
            Test_Run__c run = [
                SELECT Id, Name, Session_Id__c, Steps_Total__c,
                       Test_Script__c,
                       Test_Script__r.Name,
                       Test_Script__r.Timeout_Minutes__c,
                       Test_Script__r.Continue_On_Failure__c,
                       Test_Script__r.Run_Script_As__c,
                       Test_Script__r.Test_Suite__r.Default_Run_As__c
                FROM Test_Run__c
                WHERE Id = :testRunId
                LIMIT 1
            ];

            List<Test_Step__c> steps = [
                SELECT Id, Step_Number__c, Step_Type__c,
                       Description__c, Expected_Outcome__c,
                       Continue_On_Fail__c, Timeout_Seconds__c, Max_Actions__c
                FROM Test_Step__c
                WHERE Test_Script__c = :run.Test_Script__c
                  AND Active__c = true
                ORDER BY Step_Number__c ASC
            ];

            // Resolve the callback URL (where the service will POST results back)
            String orgUrl    = URL.getOrgDomainUrl().toExternalForm();
            String callbackUrl = orgUrl + '/services/apexrest/qatester/callback';

            // Build request payload
            Map<String, Object> payload = new Map<String, Object>{
                'sessionId'          => run.Session_Id__c,
                'testRunId'          => run.Id,
                'testScriptName'     => run.Test_Script__r.Name,
                'callbackUrl'        => callbackUrl,
                'sfAccessToken'      => UserInfo.getSessionId(),
                'timeoutMinutes'     => run.Test_Script__r.Timeout_Minutes__c != null
                                            ? run.Test_Script__r.Timeout_Minutes__c
                                            : 10,
                'continueOnFailure'  => run.Test_Script__r.Continue_On_Failure__c,
                'targetUrl'          => String.isNotBlank(targetUrl) ? targetUrl : '',
                'steps'              => buildStepPayload(steps)
            };

            // Read Bearer token from Custom Metadata
            String apiKey = '';
            List<QA_Tester_Config__mdt> configs = [
                SELECT Service_API_Key__c
                FROM QA_Tester_Config__mdt
                WHERE DeveloperName = 'Default'
                LIMIT 1
            ];
            if (!configs.isEmpty() && String.isNotBlank(configs[0].Service_API_Key__c)) {
                apiKey = configs[0].Service_API_Key__c;
            }

            // Fire the callout
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:' + namedCredential + '/execute-test');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Authorization', 'Bearer ' + apiKey);
            req.setBody(JSON.serialize(payload));
            req.setTimeout(120000); // 2 min max for the initial handshake

            Http http   = new Http();
            HttpResponse res = http.send(req);

            // Update run status based on service acknowledgement
            Test_Run__c runUpdate = new Test_Run__c(Id = testRunId);

            if (res.getStatusCode() == 200) {
                runUpdate.Status__c    = 'Running';
                runUpdate.Start_Time__c = System.now();
            } else {
                runUpdate.Status__c      = 'Error';
                runUpdate.Error_Message__c = 'Browser service returned HTTP ' + res.getStatusCode()
                    + ': ' + res.getBody();
                syncScriptLastRun(run.Test_Script__c, 'Error');
            }

            update runUpdate;

        } catch (Exception e) {
            // Update run to Error so the agent can report it
            Test_Run__c errorRun = new Test_Run__c(
                Id             = testRunId,
                Status__c      = 'Error',
                Error_Message__c = 'Callout exception: ' + e.getMessage()
            );
            update errorRun;
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private static List<Map<String, Object>> buildStepPayload(List<Test_Step__c> steps) {
        List<Map<String, Object>> stepList = new List<Map<String, Object>>();
        for (Test_Step__c s : steps) {
            stepList.add(new Map<String, Object>{
                'id'              => s.Id,
                'stepNumber'      => s.Step_Number__c,
                'stepType'        => s.Step_Type__c,
                'description'     => s.Description__c,
                'expectedOutcome' => s.Expected_Outcome__c,
                'continueOnFail'  => s.Continue_On_Fail__c,
                'timeoutSeconds'  => s.Timeout_Seconds__c != null ? s.Timeout_Seconds__c : 30,
                'maxActions'      => s.Max_Actions__c     != null ? s.Max_Actions__c     : 20
            });
        }
        return stepList;
    }

    private static void syncScriptLastRun(Id scriptId, String status) {
        update new Test_Script__c(
            Id                 = scriptId,
            Last_Run_Status__c = status,
            Last_Run_Date__c   = System.now()
        );
    }
}
