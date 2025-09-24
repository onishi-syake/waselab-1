// Test script that handles Google Apps Script redirects
const https = require('https');

const GAS_URL = 'https://script.google.com/macros/s/AKfycbxVySjk2qHoc4qaHDOjzgBYGm_Ev9sJEKwAvKPbj6JOvXxxENe7zqRZD1DM3hw3KSgV/exec';

function makeRequest(url, data, followRedirect = true) {
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
      // Handle redirect
      if (followRedirect && (res.statusCode === 302 || res.statusCode === 301)) {
        const redirectUrl = res.headers.location;
        console.log('Following redirect to:', redirectUrl.substring(0, 100) + '...');

        // Follow the redirect
        https.get(redirectUrl, (redirectRes) => {
          let data = '';
          redirectRes.on('data', chunk => data += chunk);
          redirectRes.on('end', () => {
            resolve({ status: redirectRes.statusCode, data });
          });
        });
        return;
      }

      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        resolve({ status: res.statusCode, data, headers: res.headers });
      });
    });

    req.on('error', reject);
    req.write(postData);
    req.end();
  });
}

async function testGAS() {
  console.log('=== Testing Google Apps Script (with redirect handling) ===\n');

  const testData = {
    action: 'createForm',
    userEmail: 'yudai71015@gmail.com',
    firebaseEmail: 'yudai5287@ruri.waseda.jp',
    customTitle: 'Permission Test ' + Date.now(),
    template: {
      title: 'Test Form',
      description: 'Testing permissions',
      questions: [
        {
          question: 'Name',
          type: 'shortText',
          required: true
        }
      ]
    }
  };

  console.log('Testing with:');
  console.log('- User Email:', testData.userEmail);
  console.log('- Firebase Email:', testData.firebaseEmail);
  console.log('\n');

  try {
    const response = await makeRequest(GAS_URL, testData);
    console.log('Response Status:', response.status);
    console.log('\nResponse Data:');
    console.log(response.data);
    console.log('\n');

    try {
      const result = JSON.parse(response.data);

      console.log('=== RESULTS ===');
      console.log('Success:', result.success);
      console.log('Form ID:', result.formId || 'MISSING');
      console.log('Editor Added:', result.editorAdded !== undefined ? result.editorAdded : 'MISSING');
      console.log('Sharing Mode:', result.sharingMode || 'MISSING');
      console.log('Editors Added:', result.editorsAdded || 'MISSING');
      console.log('Message:', result.message || 'MISSING');

      console.log('\n=== VALIDATION ===');
      if (result.editorAdded === false || result.editorAdded === undefined) {
        console.log('❌ PROBLEM: Editor was NOT added or field is missing');
        console.log('This is why the app shows "Editor added: false"');
      } else {
        console.log('✅ Editor was added successfully');
      }

      if (result.sharingMode === 'unknown' || !result.sharingMode) {
        console.log('❌ PROBLEM: Sharing mode is unknown or missing');
        console.log('This is why the app shows "Sharing mode: unknown"');
      } else {
        console.log('✅ Sharing mode:', result.sharingMode);
      }

      if (result.formId && result.editUrl) {
        console.log('\n📋 Form created:', result.editUrl);
      }

    } catch (e) {
      console.error('Failed to parse JSON:', e.message);
      console.log('\nThe GAS is not returning valid JSON.');
    }
  } catch (error) {
    console.error('Request failed:', error.message);
  }
}

testGAS();