/**
 * GetTestRunStatusActionTest
 * Tests for GetTestRunStatusAction @InvocableMethod
 */
@IsTest
private class GetTestRunStatusActionTest {

    @TestSetup
    static void setupData() {
        Test_Script__c script = new Test_Script__c(
            Name      = 'Status Test Script',
            Status__c = 'Active',
            Type__c   = 'Regression'
        );
        insert script;

        // Queued run
        insert new Test_Run__c(
            Test_Script__c  = script.Id,
            Status__c       = 'Queued',
            Steps_Total__c  = 5,
            Steps_Passed__c = 0,
            Steps_Failed__c = 0,
            Session_Id__c   = 'TEST-SESSION-001'
        );

        // Passed run
        insert new Test_Run__c(
            Test_Script__c   = script.Id,
            Status__c        = 'Passed',
            Steps_Total__c   = 3,
            Steps_Passed__c  = 3,
            Steps_Failed__c  = 0,
            Duration_Seconds__c = 42,
            Summary__c       = 'All 3 steps passed successfully.',
            Start_Time__c    = System.now().addMinutes(-1),
            End_Time__c      = System.now()
        );

        // Failed run
        insert new Test_Run__c(
            Test_Script__c   = script.Id,
            Status__c        = 'Failed',
            Steps_Total__c   = 3,
            Steps_Passed__c  = 2,
            Steps_Failed__c  = 1,
            Duration_Seconds__c = 18,
            Summary__c       = 'Step 3 failed: expected button not found.',
            Error_Message__c = null
        );
    }

    // ─── Tests ────────────────────────────────────────────────────────────────

    @IsTest
    static void testGetStatus_ByRunId_Queued() {
        Test_Run__c run = [SELECT Id FROM Test_Run__c WHERE Status__c = 'Queued' LIMIT 1];

        GetTestRunStatusAction.ActionInput inp = new GetTestRunStatusAction.ActionInput();
        inp.testRunId = run.Id;

        Test.startTest();
        List<GetTestRunStatusAction.ActionOutput> results =
            GetTestRunStatusAction.getStatus(new List<GetTestRunStatusAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.areEqual('Queued', results[0].status);
        Assert.isFalse(results[0].isComplete, 'Queued run is not complete');
        Assert.areEqual(5, results[0].stepsTotal);
    }

    @IsTest
    static void testGetStatus_ByRunName_Passed() {
        Test_Run__c run = [SELECT Name FROM Test_Run__c WHERE Status__c = 'Passed' LIMIT 1];

        GetTestRunStatusAction.ActionInput inp = new GetTestRunStatusAction.ActionInput();
        inp.testRunName = run.Name;

        Test.startTest();
        List<GetTestRunStatusAction.ActionOutput> results =
            GetTestRunStatusAction.getStatus(new List<GetTestRunStatusAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.areEqual('Passed', results[0].status);
        Assert.isTrue(results[0].isComplete, 'Passed run should be complete');
        Assert.areEqual(3, results[0].stepsPassed);
        Assert.areEqual(0, results[0].stepsFailed);
        Assert.isTrue(results[0].statusMessage.contains('Passed'));
    }

    @IsTest
    static void testGetStatus_Failed_HasSummary() {
        Test_Run__c run = [SELECT Id FROM Test_Run__c WHERE Status__c = 'Failed' LIMIT 1];

        GetTestRunStatusAction.ActionInput inp = new GetTestRunStatusAction.ActionInput();
        inp.testRunId = run.Id;

        Test.startTest();
        List<GetTestRunStatusAction.ActionOutput> results =
            GetTestRunStatusAction.getStatus(new List<GetTestRunStatusAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.areEqual('Failed', results[0].status);
        Assert.isTrue(results[0].isComplete);
        Assert.areEqual(1, results[0].stepsFailed);
        Assert.isTrue(results[0].summary.contains('Step 3 failed'));
    }

    @IsTest
    static void testGetStatus_NotFound() {
        GetTestRunStatusAction.ActionInput inp = new GetTestRunStatusAction.ActionInput();
        inp.testRunId = 'a00000000000000AAA'; // fake ID

        Test.startTest();
        List<GetTestRunStatusAction.ActionOutput> results =
            GetTestRunStatusAction.getStatus(new List<GetTestRunStatusAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.isFalse(results[0].isComplete);
        Assert.isTrue(results[0].statusMessage.containsIgnoreCase('No Test Run found'));
    }

    @IsTest
    static void testGetStatus_NoIdentifierProvided() {
        GetTestRunStatusAction.ActionInput inp = new GetTestRunStatusAction.ActionInput();
        // Neither testRunId nor testRunName set

        Test.startTest();
        List<GetTestRunStatusAction.ActionOutput> results =
            GetTestRunStatusAction.getStatus(new List<GetTestRunStatusAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.isFalse(results[0].isComplete);
        Assert.isTrue(results[0].statusMessage.containsIgnoreCase('Please provide'));
    }

    @IsTest
    static void testTerminalStatuses_AreComplete() {
        // Verify Error and Cancelled are also treated as complete
        Test_Script__c script = [SELECT Id FROM Test_Script__c LIMIT 1];

        Test_Run__c errorRun = new Test_Run__c(
            Test_Script__c = script.Id,
            Status__c      = 'Error',
            Steps_Total__c = 2,
            Steps_Passed__c = 0,
            Steps_Failed__c = 0,
            Error_Message__c = 'Service timeout'
        );
        insert errorRun;

        GetTestRunStatusAction.ActionInput inp = new GetTestRunStatusAction.ActionInput();
        inp.testRunId = errorRun.Id;

        Test.startTest();
        List<GetTestRunStatusAction.ActionOutput> results =
            GetTestRunStatusAction.getStatus(new List<GetTestRunStatusAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.isTrue(results[0].isComplete, 'Error status should be complete');
    }
}
