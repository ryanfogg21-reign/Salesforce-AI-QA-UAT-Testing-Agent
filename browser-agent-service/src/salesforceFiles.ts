// ─────────────────────────────────────────────────────────────────────────────
// salesforceFiles.ts — uploads step screenshots to Salesforce ContentVersion
// and creates ContentDocumentLinks to Test_Step__c and Test_Script__c
// ─────────────────────────────────────────────────────────────────────────────

import { logger } from './logger.js';

const SF_API_VERSION = 'v66.0';

export async function uploadStepScreenshot(opts: {
  sessionId:    string;
  orgBaseUrl:   string;
  sfAccessToken: string;
  stepNumber:   number;
  stepId:       string;   // Test_Step__c record ID
  testScriptId: string;   // Test_Script__c record ID
  screenshotBase64: string;
}): Promise<string | null> {
  const { sessionId, orgBaseUrl, sfAccessToken, stepNumber, stepId, testScriptId, screenshotBase64 } = opts;
  const apiBase = `${orgBaseUrl}/services/data/${SF_API_VERSION}`;
  const headers = {
    'Authorization': `Bearer ${sfAccessToken}`,
    'Content-Type':  'application/json',
  };

  try {
    // 1. Create ContentVersion — FirstPublishLocationId auto-creates the first
    //    ContentDocumentLink to Test_Step__c.
    const cvRes = await fetch(`${apiBase}/sobjects/ContentVersion/`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        Title:                  `Step ${stepNumber} Screenshot`,
        PathOnClient:           `step_${stepNumber}_screenshot.png`,
        VersionData:            screenshotBase64,
        FirstPublishLocationId: stepId,
      }),
    });

    if (!cvRes.ok) {
      const body = await cvRes.text().catch(() => '');
      logger.warn(sessionId, `ContentVersion create failed for step ${stepNumber}`, { status: cvRes.status, body });
      return null;
    }

    const { id: cvId } = await cvRes.json() as { id: string };

    // 2. Fetch ContentDocumentId from the newly created version.
    const cvDetailRes = await fetch(`${apiBase}/sobjects/ContentVersion/${cvId}?fields=ContentDocumentId`, { headers });

    if (!cvDetailRes.ok) {
      logger.warn(sessionId, `Could not retrieve ContentDocumentId for step ${stepNumber}`);
      return null;
    }

    const { ContentDocumentId } = await cvDetailRes.json() as { ContentDocumentId: string };

    // 3. Create a second ContentDocumentLink to Test_Script__c.
    const cdlRes = await fetch(`${apiBase}/sobjects/ContentDocumentLink/`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        ContentDocumentId,
        LinkedEntityId: testScriptId,
        ShareType:      'V',
      }),
    });

    if (!cdlRes.ok) {
      const body = await cdlRes.text().catch(() => '');
      logger.warn(sessionId, `ContentDocumentLink to Test_Script__c failed for step ${stepNumber}`, { body });
      // The file is still uploaded and linked to the step — treat as partial success.
    }

    logger.info(sessionId, `Screenshot uploaded for step ${stepNumber}`, { ContentDocumentId });
    return ContentDocumentId;

  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    logger.warn(sessionId, `Screenshot upload error for step ${stepNumber}: ${message}`);
    return null;
  }
}
