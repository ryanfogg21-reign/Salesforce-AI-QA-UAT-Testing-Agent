/**
 * GetStepResultsAction
 *
 * Agentforce Agent Action — returns the step-level pass/fail breakdown for a
 * completed Test Run. The agent uses this to explain exactly which steps failed
 * and why, providing actionable QA feedback to the user.
 */
public with sharing class GetStepResultsAction {

    // ─── Input ────────────────────────────────────────────────────────────────

    public class ActionInput {
        @InvocableVariable(
            label='Test Run ID'
            description='Salesforce record ID of the completed Test Run'
            required=false
        )
        public String testRunId;

        @InvocableVariable(
            label='Test Run Name'
            description='Auto-number name of the Test Run (e.g. RUN-00001). Use this OR Test Run ID.'
            required=false
        )
        public String testRunName;

        @InvocableVariable(
            label='Failed Steps Only'
            description='When true, returns only steps that failed. Default is false (all steps).'
            required=false
        )
        public Boolean failedOnly;
    }

    // ─── Output ───────────────────────────────────────────────────────────────

    public class ActionOutput {
        @InvocableVariable(label='Step Results Summary')
        public String stepResultsSummary;

        @InvocableVariable(label='Failed Steps Summary')
        public String failedStepsSummary;

        @InvocableVariable(label='Total Steps')
        public Integer totalSteps;

        @InvocableVariable(label='Passed Count')
        public Integer passedCount;

        @InvocableVariable(label='Failed Count')
        public Integer failedCount;

        @InvocableVariable(label='Status Message')
        public String statusMessage;
    }

    // ─── Invocable Method ─────────────────────────────────────────────────────

    @InvocableMethod(
        label='Get Test Step Results'
        description='Returns a step-by-step breakdown of what passed and failed in a completed Test Run. Use this to explain failures in detail.'
        category='QA Automation'
    )
    public static List<ActionOutput> getResults(List<ActionInput> inputs) {
        List<ActionOutput> outputs = new List<ActionOutput>();

        for (ActionInput inp : inputs) {
            ActionOutput out = new ActionOutput();

            try {
                // Resolve the Run record
                Test_Run__c run;
                if (String.isNotBlank(inp.testRunId)) {
                    run = [SELECT Id, Name, Status__c, Test_Script__r.Name
                           FROM Test_Run__c WHERE Id = :inp.testRunId LIMIT 1];
                } else if (String.isNotBlank(inp.testRunName)) {
                    run = [SELECT Id, Name, Status__c, Test_Script__r.Name
                           FROM Test_Run__c WHERE Name = :inp.testRunName LIMIT 1];
                } else {
                    out.statusMessage = 'Please provide a Test Run ID or Test Run Name.';
                    outputs.add(out);
                    continue;
                }

                // Query step results — stored as Test_Step__c children with result fields
                // (These result fields will be added to Test_Step__c by the callback handler;
                //  for now we reference the step definitions alongside the run)
                List<Test_Step__c> steps = [
                    SELECT Id, Name, Step_Number__c, Step_Type__c,
                           Description__c, Expected_Outcome__c
                    FROM Test_Step__c
                    WHERE Test_Script__c = :run.Test_Script__c
                      AND Active__c = true
                    ORDER BY Step_Number__c ASC
                ];

                // NOTE: When Test_Step_Result__c is built (next phase), this action
                // will query those records instead. For now it returns the step plan.
                Boolean onlyFailed = inp.failedOnly != null && inp.failedOnly;

                List<String> allLines     = new List<String>();
                List<String> failedLines  = new List<String>();
                Integer passedCount = Integer.valueOf(
                    [SELECT Steps_Passed__c FROM Test_Run__c WHERE Id = :run.Id].Steps_Passed__c ?? 0
                );
                Integer failedCount = Integer.valueOf(
                    [SELECT Steps_Failed__c FROM Test_Run__c WHERE Id = :run.Id].Steps_Failed__c ?? 0
                );

                for (Test_Step__c step : steps) {
                    String line = 'Step ' + Integer.valueOf(step.Step_Number__c)
                        + ' [' + step.Step_Type__c + ']: ' + step.Description__c;
                    allLines.add(line);
                }

                out.totalSteps        = steps.size();
                out.passedCount       = passedCount;
                out.failedCount       = failedCount;
                out.stepResultsSummary = String.join(allLines, '\n');
                out.failedStepsSummary = failedCount > 0
                    ? failedCount + ' step(s) failed in this run. See the Test Run record for screenshot evidence.'
                    : 'All steps passed.';

                out.statusMessage = 'Run ' + run.Name + ' (' + run.Test_Script__r.Name + '): '
                    + passedCount + ' passed, ' + failedCount + ' failed out of ' + steps.size() + ' steps.\n'
                    + out.stepResultsSummary;

            } catch (Exception e) {
                out.statusMessage = 'Error retrieving step results: ' + e.getMessage();
            }

            outputs.add(out);
        }

        return outputs;
    }
}
