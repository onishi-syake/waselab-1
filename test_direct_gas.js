// Direct test for the latest GAS deployment
const https = require('https');
const { URL } = require('url');

const GAS_URL = 'https://script.google.com/macros/s/AKfycbwXMqYuj4RmjkR0jDqW3fSQvNoxK4R2jFM9ZhWk4uLa_ntU4DjJnX9g4kBUCEw-xGB8/exec';

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
  console.log('=== Testing Latest GAS Deployment ===\n');
  console.log('URL:', GAS_URL);
  console.log('Time:', new Date().toISOString());
  console.log('\n');

  const testData = {
    action: 'createForm',
    userEmail: 'yudai71015@gmail.com',
    firebaseEmail: 'yudai5287@ruri.waseda.jp',
    customTitle: 'Test Form ' + Date.now(),
    template: {
      title: 'Permission Test',
      description: 'Testing automatic editor permissions',
      questions: [
        {
          question: 'Test Question',
          type: 'shortText',
          required: true
        }
      ]
    }
  };

  console.log('Creating form for:', testData.userEmail);
  console.log('Form title:', testData.customTitle);
  console.log('\n');

  try {
    console.log('Sending POST request...');
    const response = await followRedirect(GAS_URL, 'POST', JSON.stringify(testData));

    console.log('Response Status:', response.status);
    console.log('Response Length:', response.data.length, 'bytes');
    console.log('\n');

    try {
      const result = JSON.parse(response.data);

      console.log('=== PARSED RESPONSE ===');
      console.log('Success:', result.success);
      console.log('Form ID:', result.formId || 'NOT PROVIDED');
      console.log('Form URL:', result.formUrl || 'NOT PROVIDED');
      console.log('Edit URL:', result.editUrl || 'NOT PROVIDED');
      console.log('\n');

      console.log('=== PERMISSION STATUS ===');
      console.log('Editor Added:', result.editorAdded);
      console.log('Editors Added:', result.editorsAdded);
      console.log('Sharing Mode:', result.sharingMode);
      console.log('Link Sharing:', result.linkSharingEnabled);
      console.log('Message:', result.message);
      console.log('\n');

      // Check for errors
      if (result.error) {
        console.log('❌ ERROR:', result.error);
        if (result.error.includes('not supported') || result.error.includes('サポートされていません')) {
          console.log('\nThis error means FormApp.create() is not supported by the deployment account.');
          console.log('Try deploying with a different Google account (e.g., yudai71015@gmail.com)');
        }
      } else if (result.success) {
        console.log('✅ Form created successfully!');

        if (result.editorAdded) {
          console.log('✅ Editor permissions granted to:', result.sharedWith);
        } else {
          console.log('⚠️  Editor permissions were NOT granted');
        }

        if (result.linkSharingEnabled) {
          console.log('✅ Link sharing is enabled');
        }

        if (result.editUrl) {
          console.log('\n📝 Open this URL to edit the form:');
          console.log(result.editUrl);
        }
      }

    } catch (parseErr) {
      console.error('Failed to parse JSON response:', parseErr.message);
      console.log('\nRaw response (first 500 chars):');
      console.log(response.data.substring(0, 500));
    }

  } catch (error) {
    console.error('Request failed:', error.message);
  }

  console.log('\n=== Test Complete ===');
}

testGAS();