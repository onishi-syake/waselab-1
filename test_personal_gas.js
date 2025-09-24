// Test personal account GAS deployment with redirect handling
const https = require('https');
const { URL } = require('url');

const GAS_URL = 'https://script.google.com/macros/s/AKfycbyHgz7zSkZiB-RRsEvtC4AJEOAk_JyLXdZ4SdyskDpjrTq7dteyedgM2gLJT2PXygev/exec';

function followRedirect(url, method = 'GET', postData = null) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);

    const options = {
      hostname: urlObj.hostname,
      path: urlObj.pathname + urlObj.search,
      method: method,
      headers: method === 'POST' && postData ? {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData)
      } : {}
    };

    const req = https.request(options, (res) => {
      if (res.statusCode === 301 || res.statusCode === 302) {
        const redirectUrl = res.headers.location;
        console.log('Following redirect...');

        // Follow redirect with GET
        https.get(redirectUrl, (redirectRes) => {
          let data = '';
          redirectRes.on('data', chunk => data += chunk);
          redirectRes.on('end', () => {
            resolve({ status: redirectRes.statusCode, data });
          });
        });
      } else {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          resolve({ status: res.statusCode, data });
        });
      }
    });

    req.on('error', reject);

    if (method === 'POST' && postData) {
      req.write(postData);
    }

    req.end();
  });
}

async function testGAS() {
  console.log('=== Testing Personal Account GAS Deployment ===\n');
  console.log('Deployed by: yudai71015@gmail.com (personal account)');
  console.log('URL:', GAS_URL);
  console.log('Time:', new Date().toISOString());
  console.log('\n');

  // First test GET to confirm deployment
  console.log('Testing GET endpoint...');
  try {
    const getResponse = await followRedirect(GAS_URL, 'GET');
    const getResult = JSON.parse(getResponse.data);
    console.log('GET Response:', getResult.message);
    console.log('Version:', getResult.version);
    console.log('\n');
  } catch (e) {
    console.error('GET test failed:', e.message);
  }

  // Test POST for form creation
  const testData = {
    action: 'createForm',
    userEmail: 'yudai71015@gmail.com',
    firebaseEmail: 'yudai5287@ruri.waseda.jp',
    customTitle: 'Personal Account Test ' + Date.now(),
    template: {
      title: 'Permission Test',
      description: 'Testing with personal account deployment',
      questions: [
        {
          question: 'Test Question',
          type: 'shortText',
          required: true
        }
      ]
    }
  };

  console.log('Testing form creation...');
  console.log('Target user:', testData.userEmail);
  console.log('Form title:', testData.customTitle);
  console.log('\n');

  try {
    console.log('Sending POST request...');
    const response = await followRedirect(GAS_URL, 'POST', JSON.stringify(testData));

    console.log('Response Status:', response.status);
    console.log('\n');

    try {
      const result = JSON.parse(response.data);

      console.log('=== RESPONSE ===');
      console.log('Success:', result.success);
      console.log('Form ID:', result.formId || 'NOT PROVIDED');
      console.log('Form URL:', result.formUrl || 'NOT PROVIDED');
      console.log('Edit URL:', result.editUrl || 'NOT PROVIDED');
      console.log('\n');

      console.log('=== PERMISSIONS ===');
      console.log('Editor Added:', result.editorAdded);
      console.log('Editors List:', result.editorsAdded || []);
      console.log('Sharing Mode:', result.sharingMode);
      console.log('Link Sharing:', result.linkSharingEnabled);
      console.log('\n');

      if (result.error) {
        console.log('❌ ERROR:', result.error);
        if (result.error.includes('not supported') || result.error.includes('サポートされていません')) {
          console.log('\n⚠️  FormApp.create() is still not supported!');
          console.log('Please verify that the GAS is deployed with yudai71015@gmail.com');
        }
      } else if (result.success && result.formId) {
        console.log('✅ SUCCESS! Form created with ID:', result.formId);

        if (result.editorAdded === true) {
          console.log('✅ Editor permissions granted successfully');
        } else {
          console.log('⚠️  Editor permissions were NOT granted');
        }

        if (result.linkSharingEnabled === true) {
          console.log('✅ Link sharing is enabled');
        }

        if (result.editUrl) {
          console.log('\n📝 Form URL:');
          console.log(result.editUrl);
          console.log('\nアプリでもGoogle Formsが作成できるようになりました！');
        }
      } else {
        console.log('⚠️  Unexpected response format');
      }

    } catch (parseErr) {
      console.error('Failed to parse JSON:', parseErr.message);
      console.log('\nRaw response (first 500 chars):');
      console.log(response.data.substring(0, 500));
    }

  } catch (error) {
    console.error('Request failed:', error.message);
  }

  console.log('\n=== Test Complete ===');
}

testGAS();