// Test script for new Google Apps Script deployment
// Tests the complete form creation flow with permission checks

const https = require('https');

// New GAS URL (deployed by user - forms_api_final.gs - latest)
const GAS_URL = 'https://script.google.com/macros/s/AKfycbwXMqYuj4RmjkR0jDqW3fSQvNoxK4R2jFM9ZhWk4uLa_ntU4DjJnX9g4kBUCEw-xGB8/exec';

async function makeRequest(url, data) {
  return new Promise((resolve, reject) => {
    const postData = JSON.stringify(data);
    const urlObj = new URL(url);

    const options = {
      hostname: urlObj.hostname,
      path: urlObj.pathname + urlObj.search,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData)
      }
    };

    const req = https.request(options, (res) => {
      let data = '';

      res.on('data', (chunk) => {
        data += chunk;
      });

      res.on('end', () => {
        resolve({ status: res.statusCode, data });
      });
    });

    req.on('error', (e) => {
      reject(e);
    });

    req.write(postData);
    req.end();
  });
}

async function testGoogleAppsScript() {
  console.log('=== Testing New Google Apps Script Deployment ===\n');
  console.log('URL:', GAS_URL);
  console.log('Timestamp:', new Date().toISOString());
  console.log('\n');

  const testData = {
    action: 'createForm',
    userEmail: 'yudai71015@gmail.com',  // Linked Google account
    firebaseEmail: 'yudai5287@ruri.waseda.jp',  // Firebase Auth email
    customTitle: 'Test Form ' + new Date().getTime(),
    template: {
      title: 'Permission Test Form',
      description: 'Testing automatic editor permissions',
      instructions: 'This form tests if yudai71015@gmail.com gets edit access',
      questions: [
        {
          question: 'Test Question 1',
          type: 'shortText',
          required: true,
          placeholder: 'Enter your answer'
        },
        {
          question: 'Rate this test',
          type: 'scale',
          required: false,
          scaleMin: 1,
          scaleMax: 5,
          scaleMinLabel: 'Poor',
          scaleMaxLabel: 'Excellent'
        }
      ]
    }
  };

  console.log('Request Details:');
  console.log('- Action:', testData.action);
  console.log('- User Email (should get edit access):', testData.userEmail);
  console.log('- Firebase Email:', testData.firebaseEmail);
  console.log('- Form Title:', testData.customTitle);
  console.log('\n');

  try {
    console.log('Sending request to Google Apps Script...');
    const startTime = Date.now();

    const response = await makeRequest(GAS_URL, testData);

    const duration = Date.now() - startTime;
    console.log(`Response received in ${duration}ms\n`);

    console.log('HTTP Status:', response.status);
    console.log('\nRaw Response:');
    console.log(response.data);
    console.log('\n');

    try {
      const result = JSON.parse(response.data);

      console.log('=== Parsed Response ===');
      console.log('✓ Success:', result.success);
      console.log('📝 Form ID:', result.formId || 'NOT PROVIDED');
      console.log('🔗 Form URL:', result.formUrl || 'NOT PROVIDED');
      console.log('✏️  Edit URL:', result.editUrl || 'NOT PROVIDED');
      console.log('📎 Direct Edit URL:', result.directEditUrl || 'NOT PROVIDED');
      console.log('\n');

      console.log('=== Permission Details ===');
      console.log('👤 Shared With:', result.sharedWith || 'NOT PROVIDED');
      console.log('✅ Editor Added:', result.editorAdded !== undefined ? result.editorAdded : 'NOT PROVIDED');
      console.log('👥 Editors Successfully Added:', result.editorsAdded || 'NOT PROVIDED');
      console.log('❌ Editors Failed:', result.editorsFailed || 'NOT PROVIDED');
      console.log('🔓 Sharing Mode:', result.sharingMode || 'NOT PROVIDED');
      console.log('🔗 Link Sharing Enabled:', result.linkSharingEnabled !== undefined ? result.linkSharingEnabled : 'NOT PROVIDED');
      console.log('💬 Message:', result.message || 'NOT PROVIDED');
      console.log('\n');

      // Validation
      console.log('=== Validation Results ===');

      let issues = [];

      if (!result.formId) {
        issues.push('❌ Form ID is missing');
      } else {
        console.log('✅ Form ID exists');
      }

      if (result.editorAdded === true) {
        console.log('✅ Editor was successfully added');
      } else if (result.editorAdded === false) {
        issues.push('❌ Editor was NOT added - this is the main issue!');
      } else {
        issues.push('❌ editorAdded field is missing from response');
      }

      if (result.sharingMode === 'anyone_with_link_can_edit') {
        console.log('✅ Link sharing is properly configured');
      } else if (result.sharingMode === 'unknown' || !result.sharingMode) {
        issues.push('❌ Sharing mode is unknown or missing');
      } else {
        console.log('⚠️  Sharing mode:', result.sharingMode);
      }

      if (result.editorsAdded && result.editorsAdded.includes('yudai71015@gmail.com')) {
        console.log('✅ yudai71015@gmail.com was added as editor');
      } else {
        issues.push('❌ yudai71015@gmail.com was NOT added as editor');
      }

      console.log('\n');

      if (issues.length > 0) {
        console.log('=== ISSUES FOUND ===');
        issues.forEach(issue => console.log(issue));
        console.log('\nThe Google Apps Script is not returning complete permission data.');
        console.log('This means the GAS code may not be executing the permission logic properly.');
      } else {
        console.log('🎉 All validations passed! The form should be editable.');
      }

      if (result.formId && result.editUrl) {
        console.log('\n=== Next Steps ===');
        console.log('1. Open this URL in a browser:', result.editUrl);
        console.log('2. Check if yudai71015@gmail.com can edit without permission request');
        console.log('3. If not, the issue is in the Google Apps Script permission logic');
      }

    } catch (parseError) {
      console.error('❌ Failed to parse response as JSON:', parseError.message);
      console.log('\nThis indicates the Google Apps Script may be returning an error or HTML instead of JSON.');

      // Check if it's an HTML error page
      if (response.data.includes('<!DOCTYPE') || response.data.includes('<html')) {
        console.log('The response appears to be an HTML error page.');
        console.log('Common causes:');
        console.log('- Invalid deployment URL');
        console.log('- GAS execution error');
        console.log('- Permission issues with the deployment');
      }
    }

  } catch (error) {
    console.error('\n❌ Request failed:', error.message);
    console.log('\nPossible causes:');
    console.log('- Network connectivity issues');
    console.log('- Invalid GAS URL');
    console.log('- GAS deployment not accessible');
  }

  console.log('\n=== Test Complete ===');
  console.log('Timestamp:', new Date().toISOString());
}

// Run the test
testGoogleAppsScript();