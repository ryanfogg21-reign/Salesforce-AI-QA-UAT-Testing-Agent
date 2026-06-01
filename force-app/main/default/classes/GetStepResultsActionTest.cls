/**
 * GetStepResultsActionTest
 * Tests for GetStepResultsAction @InvocableMethod
 */
@IsTest
private class GetStepResultsActionTest {

    @TestSetup
    static void setupData() {
        Test_Script__c script = new Test_Script__c(
            Name      = 'Step Results Test Script',
            Status__c = 'Active',
            Type__c   = 'Regression'
        );
        insert script;

        List<Test_Step__c> steps = new List<Test_Step__c>{
            new Test_Step__c(
                Test_Script__c      = script.Id,
                Step_Number__c      = 10,
                Step_Type__c        = 'Navigate',
                Description__c      = 'Go to Accounts tab',
                Expected_Outcome__c = 'Accounts list view shown',
                Active__c           = true
            ),
            new Test_Step__c(
                Test_Script__c      = script.Id,
                Step_Number__c      = 20,
                Step_Type__c        = 'Click',
                Description__c      = 'Click New Account button',
                Expected_Outcome__c = 'New Account form opens',
                Active__c           = true
            ),
            new Test_Step__c(
                Test_Script__c      = script.Id,
                Step_Number__c      = 30,
                Step_Type__c        = 'Fill',
                Description__c      = 'Enter Account Name',
                Expected_Outcome__c = 'Name field populated',
                Active__c           = true
            ),
            new Test_Step__c(
                Test_Script__c      = script.Id,
                Step_Number__c      = 40,
                Step_Type__c        = 'Click',
                Description__c      = 'Click Save',
                Expected_Outcome__c = 'Account record saved and detail page shown',
                Active__c           = false // inactive — should not be counted
            )
        };
        insert steps;

        // Passed run
        insert new Test_Run__c(
            Test_Script__c   = script.Id,
            Status__c        = 'Passed',
            Steps_Total__c   = 3,
            Steps_Passed__c  = 3,
            Steps_Failed__c  = 0,
            Summary__c       = 'All steps passed.'
        );

        // Failed run
        insert new Test_Run__c(
            Test_Script__c   = script.Id,
            Status__c        = 'Failed',
            Steps_Total__c   = 3,
            Steps_Passed__c  = 2,
            Steps_Failed__c  = 1,
            Summary__c       = 'Step 3 failed: field not found.'
        );
    }

    // ─── Tests ────────────────────────────────────────────────────────────────

    @IsTest
    static void testGetResults_ByRunId_Passed() {
        Test_Run__c run = [SELECT Id FROM Test_Run__c WHERE Status__c = 'Passed' LIMIT 1];

        GetStepResultsAction.ActionInput inp = new GetStepResultsAction.ActionInput();
        inp.testRunId = run.Id;

        Test.startTest();
        List<GetStepResultsAction.ActionOutput> results =
            GetStepResultsAction.getResults(new List<GetStepResultsAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.areEqual(3, results[0].totalSteps, 'Should count only active steps (3 of 4)');
        Assert.areEqual(3, results[0].passedCount);
        Assert.areEqual(0, results[0].failedCount);
        Assert.isTrue(results[0].failedStepsSummary.contains('All steps passed'));
    }

    @IsTest
    static void testGetResults_ByRunName_Failed() {
        Test_Run__c run = [SELECT Name FROM Test_Run__c WHERE Status__c = 'Failed' LIMIT 1];

        GetStepResultsAction.ActionInput inp = new GetStepResultsAction.ActionInput();
        inp.testRunName = run.Name;

        Test.startTest();
        List<GetStepResultsAction.ActionOutput> results =
            GetStepResultsAction.getResults(new List<GetStepResultsAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.areEqual(1, results[0].failedCount);
        Assert.isTrue(results[0].failedStepsSummary.containsIgnoreCase('failed'));
    }

    @IsTest
    static void testGetResults_StepSummaryHasStepNumbers() {
        Test_Run__c run = [SELECT Id FROM Test_Run__c LIMIT 1];

        GetStepResultsAction.ActionInput inp = new GetStepResultsAction.ActionInput();
        inp.testRunId = run.Id;

        Test.startTest();
        List<GetStepResultsAction.ActionOutput> results =
            GetStepResultsAction.getResults(new List<GetStepResultsAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.isTrue(results[0].stepResultsSummary.contains('Step 10'), 'Summary should include step numbers');
        Assert.isTrue(results[0].stepResultsSummary.contains('Navigate'), 'Summary should include step type');
        Assert.isFalse(results[0].stepResultsSummary.contains('Step 40'),
            'Inactive steps (step 40) should not appear');
    }

    @IsTest
    static void testGetResults_NotFound() {
        GetStepResultsAction.ActionInput inp = new GetStepResultsAction.ActionInput();
        inp.testRunId = 'a00000000000000AAA';

        Test.startTest();
        List<GetStepResultsAction.ActionOutput> results =
            GetStepResultsAction.getResults(new List<GetStepResultsAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.isTrue(results[0].statusMessage.containsIgnoreCase('error') ||
                      results[0].statusMessage.containsIgnoreCase('not found') ||
                      results[0].statusMessage.containsIgnoreCase('No such'),
            'Should return an error message for invalid ID');
    }

    @IsTest
    static void testGetResults_NoIdentifier() {
        GetStepResultsAction.ActionInput inp = new GetStepResultsAction.ActionInput();

        Test.startTest();
        List<GetStepResultsAction.ActionOutput> results =
            GetStepResultsAction.getResults(new List<GetStepResultsAction.ActionInput>{ inp });
        Test.stopTest();

        Assert.isTrue(results[0].statusMessage.containsIgnoreCase('Please provide'));
    }
}
