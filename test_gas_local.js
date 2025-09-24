// ローカルテスト用スクリプト
// Google Apps Scriptの動作を確認

const fetch = require('node-fetch');

// Google Apps Script URL（デプロイ後に更新してください）
const GAS_URL = 'YOUR_GAS_URL_HERE';

async function testFormCreation() {
  console.log('=== Testing Google Apps Script ===\n');

  const requestData = {
    action: 'createForm',
    userEmail: 'yudai71015@gmail.com',
    firebaseEmail: 'yudai5287@ruri.waseda.jp',
    template: {
      title: 'Test Form ' + Date.now(),
      description: 'テストフォームです',
      instructions: 'すべての質問に回答してください',
      questions: [
        {
          question: 'お名前',
          type: 'shortText',
          required: true,
          placeholder: '山田太郎'
        },
        {
          question: '満足度',
          type: 'scale',
          required: true,
          scaleMin: 1,
          scaleMax: 5,
          scaleMinLabel: '不満',
          scaleMaxLabel: '満足'
        },
        {
          question: '同意事項',
          type: 'checkbox',
          required: true,
          options: ['同意します']
        }
      ]
    }
  };

  console.log('Request Data:');
  console.log('- Action:', requestData.action);
  console.log('- User Email:', requestData.userEmail);
  console.log('- Firebase Email:', requestData.firebaseEmail);
  console.log('- Form Title:', requestData.template.title);
  console.log('- Questions Count:', requestData.template.questions.length);
  console.log('\n');

  try {
    console.log('Sending request to Google Apps Script...');
    const response = await fetch(GAS_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(requestData),
    });

    const responseText = await response.text();
    console.log('\nRaw Response:', responseText);

    try {
      const result = JSON.parse(responseText);
      console.log('\n=== Parsed Response ===');
      console.log('Success:', result.success);
      console.log('Form ID:', result.formId);
      console.log('Form URL:', result.formUrl);
      console.log('Edit URL:', result.editUrl);
      console.log('Shared With:', result.sharedWith);
      console.log('Editor Added:', result.editorAdded);
      console.log('Editors Added:', result.editorsAdded);
      console.log('Editors Failed:', result.editorsFailed);
      console.log('Sharing Mode:', result.sharingMode);
      console.log('Link Sharing Enabled:', result.linkSharingEnabled);
      console.log('Message:', result.message);

      // 成功チェック
      console.log('\n=== Validation ===');
      if (result.editorAdded) {
        console.log('✅ Editor was successfully added');
      } else {
        console.log('❌ Editor was NOT added');
      }

      if (result.linkSharingEnabled) {
        console.log('✅ Link sharing is enabled');
      } else {
        console.log('❌ Link sharing is NOT enabled');
      }

      if (result.sharingMode === 'anyone_with_link_can_edit') {
        console.log('✅ Sharing mode is correct');
      } else {
        console.log('❌ Sharing mode is incorrect:', result.sharingMode);
      }

      if (result.formId) {
        console.log('\n📋 Form created successfully!');
        console.log('Open this URL to edit the form:', result.editUrl);
      }

    } catch (parseError) {
      console.error('Failed to parse response:', parseError);
    }

  } catch (error) {
    console.error('Request failed:', error);
  }
}

// 実行
if (GAS_URL === 'YOUR_GAS_URL_HERE') {
  console.log('⚠️  Please update GAS_URL with your deployed Google Apps Script URL');
} else {
  testFormCreation();
}