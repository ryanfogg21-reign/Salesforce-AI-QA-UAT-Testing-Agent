/**
 * TestRunCallbackResource
 *
 * REST endpoint that receives the final test result from the browser
 * automation microservice once a run completes.
 *
 * The microservice POSTs to:
 *   POST /services/apexrest/qatester/callback
 *
 * Expected payload:
 * {
 *   "sessionId": "SF-17xxxxx-005xxxx",
 *   "testRunId": "a0Bxx000000xxxxx",
 *   "status":    "Passed" | "Failed" | "Error",
 *   "summary":   "All 5 steps passed...",
 *   "errorMessage": null,
 *   "durationSeconds": 42,
 *   "stepsPassed": 5,
 *   "stepsFailed": 0,
 *   "stepsTotal":  5
 * }
 */
@RestResource(urlMapping='/qatester/callback')
global with sharing class TestRunCallbackResource {

    @HttpPost
    global static void handleCallback() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            Map<String, Object> body =
                (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());

            String runId         = (String)  body.get('testRunId');
            String status        = (String)  body.get('status');
            String summary       = (String)  body.get('summary');
            String errorMsg      = (String)  body.get('errorMessage');
            Integer durationSecs = body.get('durationSeconds') != null
                                    ? Integer.valueOf(body.get('durationSeconds')) : null;
            Integer stepsPassed  = body.get('stepsPassed') != null
                                    ? Integer.valueOf(body.get('stepsPassed'))  : 0;
            Integer stepsFailed  = body.get('stepsFailed') != null
                                    ? Integer.valueOf(body.get('stepsFailed'))  : 0;
            Integer stepsTotal   = body.get('stepsTotal')  != null
                                    ? Integer.valueOf(body.get('stepsTotal'))   : 0;

            if (String.isBlank(runId) || String.isBlank(status)) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf('{"error":"testRunId and status are required"}');
                return;
            }

            // Update the Test Run
            Test_Run__c run = [
                SELECT Id, Test_Script__c, Start_Time__c
                FROM Test_Run__c WHERE Id = :runId LIMIT 1
            ];

            run.Status__c         = status;
            run.Summary__c        = summary;
            run.Error_Message__c  = errorMsg;
            run.End_Time__c       = System.now();
            run.Duration_Seconds__c = durationSecs;
            run.Steps_Passed__c   = stepsPassed;
            run.Steps_Failed__c   = stepsFailed;
            run.Steps_Total__c    = stepsTotal;
            update run;

            // Sync Last Run fields back to the Test Script
            update new Test_Script__c(
                Id                 = run.Test_Script__c,
                Last_Run_Status__c = status,
                Last_Run_Date__c   = System.now()
            );

            res.statusCode = 200;
            res.responseBody = Blob.valueOf('{"success":true}');

        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf('{"error":"' + e.getMessage() + '"}');
        }
    }
}
