/**
 * RunTestScriptActionTest
 * Tests for RunTestScriptAction @InvocableMethod
 */
@IsTest
private class RunTestScriptActionTest {

    // ─── Test Data Setup ──────────────────────────────────────────────────────

    @TestSetup
    static void setupData() {
        // Create a Test Suite — intentionally NO Named Credential so the callout
        // branch is not triggered and we can assert the Queued status cleanly.
        // A separate test with an HttpCalloutMock covers the callout path.
        Test_Suite__c suite = new Test_Suite__c(
            Name              = 'Test Suite - Unit Tests',
            Active__c         = true,
            Target_Org_URL__c = 'https://test.salesforce.com'
        );
        insert suite;

        // Create an Active Test Script with steps
        Test_Script__c activeScript = new Test_Script__c(
            Name              = 'Active Script With Steps',
            Status__c         = 'Active',
            Type__c           = 'Regression',
            Test_Suite__c     = suite.Id,
            Timeout_Minutes__c = 10,
            Continue_On_Failure__c = false
        );
        insert activeScript;

        // Create an Active Test Script with NO steps
        Test_Script__c noStepsScript = new Test_Script__c(
            Name      = 'Active Script No Steps',
            Status__c = 'Active',
            Type__c   = 'Smoke'
        );
        insert noStepsScript;

        // Create a Draft (inactive) script
        Test_Script__c draftScript = new Test_Script__c(
            Name      = 'Draft Script',
            Status__c = 'Draft',
            Type__c   = 'Functional'
        );
        insert draftScript;

        // Add steps to the active script
        List<Test_Step__c> steps = new List<Test_Step__c>{
            new Test_Step__c(
                Test_Script__c   = activeScript.Id,
                Step_Number__c   = 10,
                Step_Type__c     = 'Navigate',
                Description__c   = 'Navigate to Opportunities tab',
                Expected_Outcome__c = 'Opportunities list view is displayed',
                Active__c        = true
            ),
            new Test_Step__c(
                Test_Script__c   = activeScript.Id,
                Step_Number__c   = 20,
                Step_Type__c     = 'Click',
                Description__c   = 'Click the New button',
                Expected_Outcome__c = 'New Opportunity form opens',
                Active__c        = true
            )
        };
        insert steps;
    }

    // ─── Tests ────────────────────────────────────────────────────────────────

    @IsTest
    static void testRunActiveScript_Success() {
        RunTestScriptAction.ActionInput inp = new RunTestScriptAction.ActionInput();
        inp.testScriptName = 'Active Script With Steps';

        Test.startTest();
        List<RunTestScriptAction.ActionOutput> results =
            RunTestScriptAction.run(new List<RunTestScriptAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Should return one output');
        RunTestScriptAction.ActionOutput out = results[0];
        Assert.isTrue(out.success, 'Should succeed for active script with steps');
        Assert.isNotNull(out.testRunId, 'Should return a Test Run ID');
        Assert.isNotNull(out.testRunName, 'Should return a Test Run Name');
        Assert.isTrue(out.statusMessage.contains('Active Script With Steps'),
            'Status message should include script name');

        // Verify the Test Run record was created
        List<Test_Run__c> runs = [SELECT Id, Status__c, Steps_Total__c FROM Test_Run__c];
        Assert.areEqual(1, runs.size(), 'Should create one Test Run record');
        Assert.areEqual('Queued', runs[0].Status__c, 'Run should be Queued');
        Assert.areEqual(2, Integer.valueOf(runs[0].Steps_Total__c), 'Should count 2 active steps');
    }

    @IsTest
    static void testRunScript_NotFound() {
        RunTestScriptAction.ActionInput inp = new RunTestScriptAction.ActionInput();
        inp.testScriptName = 'Non-Existent Script Name XYZ';

        Test.startTest();
        List<RunTestScriptAction.ActionOutput> results =
            RunTestScriptAction.run(new List<RunTestScriptAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.isFalse(results[0].success, 'Should fail for non-existent script');
        Assert.isTrue(results[0].statusMessage.contains('Non-Existent Script Name XYZ'),
            'Error should include the script name attempted');
        Assert.areEqual(0, [SELECT COUNT() FROM Test_Run__c], 'Should not create any run record');
    }

    @IsTest
    static void testRunDraftScript_Rejected() {
        // Draft scripts should NOT be found (query filters on Status__c = 'Active')
        RunTestScriptAction.ActionInput inp = new RunTestScriptAction.ActionInput();
        inp.testScriptName = 'Draft Script';

        Test.startTest();
        List<RunTestScriptAction.ActionOutput> results =
            RunTestScriptAction.run(new List<RunTestScriptAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.isFalse(results[0].success, 'Should fail for Draft script');
    }

    @IsTest
    static void testRunScript_NoActiveSteps() {
        RunTestScriptAction.ActionInput inp = new RunTestScriptAction.ActionInput();
        inp.testScriptName = 'Active Script No Steps';

        Test.startTest();
        List<RunTestScriptAction.ActionOutput> results =
            RunTestScriptAction.run(new List<RunTestScriptAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.isFalse(results[0].success, 'Should fail with no steps');
        Assert.isTrue(results[0].statusMessage.containsIgnoreCase('no active'),
            'Error should mention no active steps');
        Assert.areEqual(0, [SELECT COUNT() FROM Test_Run__c], 'Should not create a run');
    }

    @IsTest
    static void testRunScript_WithTargetUrlOverride() {
        RunTestScriptAction.ActionInput inp = new RunTestScriptAction.ActionInput();
        inp.testScriptName       = 'Active Script With Steps';
        inp.targetOrgUrlOverride = 'https://mycompany--uat.sandbox.my.salesforce.com';

        Test.startTest();
        List<RunTestScriptAction.ActionOutput> results =
            RunTestScriptAction.run(new List<RunTestScriptAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.isTrue(results[0].success, 'Should succeed with URL override');
    }

    @IsTest
    static void testRunScript_WithNamedCredential_CalloutMocked() {
        // Update the suite to have a Named Credential for this test only
        Test_Suite__c suite = [SELECT Id FROM Test_Suite__c LIMIT 1];
        suite.Named_Credential_API_Name__c = 'Browser_Agent_Service';
        update suite;

        RunTestScriptAction.ActionInput inp = new RunTestScriptAction.ActionInput();
        inp.testScriptName = 'Active Script With Steps';

        Test.setMock(HttpCalloutMock.class, new BrowserServiceMock(200, '{"status":"running"}'));
        Test.startTest();
        List<RunTestScriptAction.ActionOutput> results =
            RunTestScriptAction.run(new List<RunTestScriptAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.isTrue(results[0].success, 'Should succeed when service responds 200');
        Test_Run__c run = [SELECT Status__c FROM Test_Run__c ORDER BY CreatedDate DESC LIMIT 1];
        // After stopTest, the @future runs — service mock returned 200 so status = Running
        Assert.areEqual('Running', run.Status__c, 'Run should be Running after successful callout');
    }

    @IsTest
    static void testBulkInvocation() {
        // Test that multiple inputs are processed independently
        RunTestScriptAction.ActionInput inp1 = new RunTestScriptAction.ActionInput();
        inp1.testScriptName = 'Active Script With Steps';

        RunTestScriptAction.ActionInput inp2 = new RunTestScriptAction.ActionInput();
        inp2.testScriptName = 'Does Not Exist';

        Test.startTest();
        List<RunTestScriptAction.ActionOutput> results =
            RunTestScriptAction.run(
                new List<RunTestScriptAction.ActionInput>{ inp1, inp2 }
            );
        Test.stopTest();

        Assert.areEqual(2, results.size(), 'Should return 2 outputs');
        Assert.isTrue(results[0].success,  'First input should succeed');
        Assert.isFalse(results[1].success, 'Second input should fail');
    }

    // ─── Mock HTTP Callout ────────────────────────────────────────────────────

    private class BrowserServiceMock implements HttpCalloutMock {
        private Integer statusCode;
        private String  body;

        public BrowserServiceMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body       = body;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(this.statusCode);
            res.setBody(this.body);
            res.setHeader('Content-Type', 'application/json');
            return res;
        }
    }
}
