// Google Apps Script - Simple Forms API
// シンプルで確実に動作するバージョン

function doPost(e) {
  try {
    console.log('=== doPost START ===');
    console.log('Raw request:', e.postData.contents);

    const data = JSON.parse(e.postData.contents);
    console.log('Parsed data - action:', data.action);
    console.log('Parsed data - userEmail:', data.userEmail);
    console.log('Parsed data - firebaseEmail:', data.firebaseEmail);

    if (data.action === 'createForm') {
      // フォーム作成
      const template = data.template;
      const title = data.customTitle || template.title || 'New Form';

      console.log('Creating form with title:', title);
      const form = FormApp.create(title);
      const formId = form.getId();
      const formUrl = form.getPublishedUrl();
      const editUrl = form.getEditUrl();

      console.log('Form created successfully');
      console.log('Form ID:', formId);
      console.log('Form URL:', formUrl);
      console.log('Edit URL:', editUrl);

      // 基本設定
      form.setRequireLogin(false);
      form.setCollectEmail(true);
      form.setLimitOneResponsePerUser(false);
      form.setShowLinkToRespondAgain(true);
      console.log('Basic settings applied');

      // 説明を設定
      if (template.description || template.instructions) {
        const description = [template.description, template.instructions]
          .filter(Boolean)
          .join('\n\n');
        form.setDescription(description);
        console.log('Description set');
      }

      // 質問を追加
      if (template.questions && template.questions.length > 0) {
        console.log('Adding', template.questions.length, 'questions');
        for (let i = 0; i < template.questions.length; i++) {
          try {
            addQuestionToForm(form, template.questions[i]);
            console.log('Added question', i + 1);
          } catch (qErr) {
            console.error('Failed to add question', i + 1, ':', qErr.toString());
          }
        }
      }

      // 共有設定
      let sharingSet = false;
      let editorAdded = false;
      const editorsAdded = [];
      const editorsFailed = [];

      console.log('Starting sharing settings...');

      try {
        const file = DriveApp.getFileById(formId);
        console.log('Got file reference');

        // リンク共有を設定
        try {
          file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.EDIT);
          sharingSet = true;
          console.log('Link sharing enabled: Anyone with link can edit');
        } catch (shareErr) {
          console.error('Could not enable link sharing:', shareErr.toString());
        }

        // ユーザーを編集者として追加（優先順位: userEmail > firebaseEmail）
        const emailsToTry = [];

        if (data.userEmail && data.userEmail.includes('@')) {
          emailsToTry.push(data.userEmail);
          console.log('Will try to add userEmail:', data.userEmail);
        }

        if (data.firebaseEmail && data.firebaseEmail.includes('@') &&
            data.firebaseEmail !== data.userEmail) {
          emailsToTry.push(data.firebaseEmail);
          console.log('Will try to add firebaseEmail:', data.firebaseEmail);
        }

        // 各メールアドレスで編集者追加を試みる
        for (const email of emailsToTry) {
          console.log('Attempting to add editor:', email);
          try {
            file.addEditor(email);
            editorsAdded.push(email);
            editorAdded = true;
            console.log('Successfully added editor:', email);

            // 確認
            const editors = file.getEditors();
            const found = editors.some(e => {
              const editorEmail = e.getEmail();
              return editorEmail && editorEmail.toLowerCase() === email.toLowerCase();
            });
            console.log('Editor verification for', email, ':', found);

          } catch (addErr) {
            console.error('Failed to add editor', email, ':', addErr.toString());
            editorsFailed.push({
              email: email,
              error: addErr.toString()
            });
          }
        }

      } catch (fileErr) {
        console.error('File operation error:', fileErr.toString());
      }

      // レスポンスを作成（必ずすべてのフィールドを含める）
      const response = {
        success: true,
        formId: formId,
        formUrl: formUrl,
        editUrl: editUrl,
        directEditUrl: editUrl,
        sharedWith: editorsAdded.length > 0 ? editorsAdded[0] : (data.userEmail || null),
        editorAdded: editorAdded,
        editorsAdded: editorsAdded,
        editorsFailed: editorsFailed,
        sharingMode: sharingSet ? 'anyone_with_link_can_edit' : 'restricted',
        linkSharingEnabled: sharingSet,
        timestamp: new Date().toISOString(),
        message: (editorAdded || sharingSet)
          ? 'フォームが作成され、編集権限が設定されました'
          : 'フォームは作成されましたが、編集権限の設定に失敗しました'
      };

      console.log('=== RESPONSE ===');
      console.log(JSON.stringify(response));
      console.log('=== doPost END ===');

      return ContentService.createTextOutput(JSON.stringify(response))
        .setMimeType(ContentService.MimeType.JSON);
    }

    // Unknown action
    return ContentService.createTextOutput(JSON.stringify({
      success: false,
      error: 'Unknown action: ' + data.action
    })).setMimeType(ContentService.MimeType.JSON);

  } catch (error) {
    console.error('=== ERROR in doPost ===');
    console.error(error.toString());
    console.error('Stack:', error.stack);

    return ContentService.createTextOutput(JSON.stringify({
      success: false,
      error: error.toString(),
      stack: error.stack || 'No stack trace'
    })).setMimeType(ContentService.MimeType.JSON);
  }
}

// 質問をフォームに追加
function addQuestionToForm(form, question) {
  let item;

  switch (question.type) {
    case 'multipleChoice':
      item = form.addMultipleChoiceItem();
      item.setTitle(question.question);
      if (question.options && question.options.length > 0) {
        item.setChoiceValues(question.options);
      }
      break;

    case 'checkbox':
      item = form.addCheckboxItem();
      item.setTitle(question.question);
      if (question.options && question.options.length > 0) {
        item.setChoiceValues(question.options);
      }
      break;

    case 'scale':
      item = form.addScaleItem();
      item.setTitle(question.question);
      item.setBounds(question.scaleMin || 1, question.scaleMax || 5);
      if (question.scaleMinLabel) {
        item.setLabels(question.scaleMinLabel, question.scaleMaxLabel || '');
      }
      break;

    case 'shortText':
      item = form.addTextItem();
      item.setTitle(question.question);
      break;

    case 'longText':
      item = form.addParagraphTextItem();
      item.setTitle(question.question);
      break;

    case 'date':
      item = form.addDateItem();
      item.setTitle(question.question);
      break;

    case 'time':
      item = form.addTimeItem();
      item.setTitle(question.question);
      break;

    default:
      // デフォルトはテキスト
      item = form.addTextItem();
      item.setTitle(question.question);
  }

  // 必須設定
  if (item && question.required === true) {
    item.setRequired(true);
  }

  // ヘルプテキスト
  if (item && question.placeholder) {
    item.setHelpText(question.placeholder);
  }
}

// GETリクエスト用（動作確認）
function doGet(e) {
  return ContentService.createTextOutput(JSON.stringify({
    success: true,
    message: 'Google Forms API (Simple Version) is ready',
    version: '3.0',
    timestamp: new Date().toISOString()
  })).setMimeType(ContentService.MimeType.JSON);
}

// テスト関数（こちらを実行してください）
function testCreateForm() {
  console.log('=== TEST START ===');

  const testRequest = {
    postData: {
      contents: JSON.stringify({
        action: 'createForm',
        userEmail: 'yudai71015@gmail.com',
        firebaseEmail: 'yudai5287@ruri.waseda.jp',
        customTitle: 'テストフォーム_' + new Date().getTime(),
        template: {
          title: 'テストフォーム',
          description: 'これはテストフォームです',
          instructions: 'すべての質問に回答してください',
          questions: [
            {
              question: 'お名前を入力してください',
              type: 'shortText',
              required: true,
              placeholder: '山田太郎'
            },
            {
              question: '満足度を教えてください',
              type: 'scale',
              required: true,
              scaleMin: 1,
              scaleMax: 5,
              scaleMinLabel: '不満',
              scaleMaxLabel: '満足'
            },
            {
              question: '同意しますか？',
              type: 'checkbox',
              required: true,
              options: ['同意します']
            }
          ]
        }
      })
    }
  };

  console.log('Calling doPost with test data...');

  try {
    const result = doPost(testRequest);
    const responseContent = result.getContent();
    console.log('Raw Response:', responseContent);

    const response = JSON.parse(responseContent);

    console.log('\n=== TEST RESULTS ===');
    console.log('✅ Success:', response.success);
    console.log('📝 Form ID:', response.formId);
    console.log('🔗 Form URL:', response.formUrl);
    console.log('✏️ Edit URL:', response.editUrl);
    console.log('👤 Shared With:', response.sharedWith);
    console.log('✅ Editor Added:', response.editorAdded);
    console.log('👥 Editors Added:', JSON.stringify(response.editorsAdded));
    console.log('❌ Editors Failed:', JSON.stringify(response.editorsFailed));
    console.log('🔓 Sharing Mode:', response.sharingMode);
    console.log('🔗 Link Sharing:', response.linkSharingEnabled);
    console.log('💬 Message:', response.message);

    // 検証
    console.log('\n=== VALIDATION ===');
    if (response.editorAdded === true) {
      console.log('✅ SUCCESS: Editor was added');
    } else {
      console.log('❌ FAIL: Editor was NOT added');
    }

    if (response.linkSharingEnabled === true) {
      console.log('✅ SUCCESS: Link sharing is enabled');
    } else {
      console.log('❌ FAIL: Link sharing is NOT enabled');
    }

    if (response.sharingMode === 'anyone_with_link_can_edit') {
      console.log('✅ SUCCESS: Correct sharing mode');
    } else {
      console.log('❌ FAIL: Wrong sharing mode:', response.sharingMode);
    }

    if (response.formId) {
      console.log('\n🎉 Form created successfully!');
      console.log('📋 Form ID:', response.formId);
      console.log('🔗 Open this URL to edit:', response.editUrl);
    }

  } catch (error) {
    console.error('Test failed:', error.toString());
    console.error('Stack:', error.stack);
  }

  console.log('\n=== TEST END ===');
}

// 簡単なテスト（最小限のテスト）
function quickTest() {
  console.log('=== QUICK TEST ===');

  // 最小限のデータでテスト
  const minimalRequest = {
    postData: {
      contents: JSON.stringify({
        action: 'createForm',
        userEmail: 'yudai71015@gmail.com',
        template: {
          title: 'Quick Test ' + new Date().getTime(),
          questions: []
        }
      })
    }
  };

  try {
    const result = doPost(minimalRequest);
    const response = JSON.parse(result.getContent());

    console.log('Success:', response.success);
    console.log('Form ID:', response.formId);
    console.log('Editor Added:', response.editorAdded);
    console.log('Sharing Mode:', response.sharingMode);

    if (response.success && response.formId) {
      console.log('✅ Quick test passed!');
      console.log('Form URL:', response.editUrl);
    } else {
      console.log('❌ Quick test failed');
    }
  } catch (e) {
    console.error('Quick test error:', e.toString());
  }
}