// Google Apps Script - Forms API Final Version
// 確実に動作する最終版 - エラー対策とログ強化

function doPost(e) {
  // エラーが発生しても必ず値を返すように初期化
  let response = {
    success: false,
    formId: null,
    formUrl: null,
    editUrl: null,
    directEditUrl: null,
    sharedWith: null,
    editorAdded: false,
    editorsAdded: [],
    editorsFailed: [],
    sharingMode: 'unknown',
    linkSharingEnabled: false,
    timestamp: new Date().toISOString(),
    message: 'Processing...'
  };

  try {
    console.log('=== doPost START ===');
    console.log('Raw request:', e.postData.contents);

    const data = JSON.parse(e.postData.contents);
    console.log('Action:', data.action);
    console.log('User Email:', data.userEmail);
    console.log('Firebase Email:', data.firebaseEmail);

    if (data.action !== 'createForm') {
      response.message = 'Invalid action: ' + data.action;
      return ContentService.createTextOutput(JSON.stringify(response))
        .setMimeType(ContentService.MimeType.JSON);
    }

    // フォーム作成
    const template = data.template || {};
    const title = data.customTitle || template.title || 'New Form ' + Date.now();

    console.log('Creating form:', title);

    // FormApp.create()がサポートされているかチェック
    let form, formId, formUrl, editUrl;
    try {
      form = FormApp.create(title);
      formId = form.getId();
      formUrl = form.getPublishedUrl();
      editUrl = form.getEditUrl();

      response.formId = formId;
      response.formUrl = formUrl;
      response.editUrl = editUrl;
      response.directEditUrl = editUrl;

      console.log('Form created successfully');
      console.log('Form ID:', formId);
    } catch (formErr) {
      console.error('Form creation error:', formErr.toString());
      response.message = 'フォーム作成エラー: ' + formErr.toString();

      // FormApp.create()がサポートされていない場合の代替処理
      if (formErr.toString().includes('サポートされていません') ||
          formErr.toString().includes('not supported')) {
        response.message = 'Google Apps Scriptの実行アカウントでFormApp.create()がサポートされていません。別の方法を試してください。';
      }

      return ContentService.createTextOutput(JSON.stringify(response))
        .setMimeType(ContentService.MimeType.JSON);
    }

    // フォーム設定
    try {
      form.setRequireLogin(false);
      form.setCollectEmail(true);
      form.setLimitOneResponsePerUser(false);
      form.setShowLinkToRespondAgain(true);
      console.log('Form settings applied');
    } catch (settingsErr) {
      console.error('Settings error (non-critical):', settingsErr.toString());
    }

    // 説明追加
    if (template.description || template.instructions) {
      try {
        const desc = [template.description, template.instructions]
          .filter(Boolean)
          .join('\n\n');
        form.setDescription(desc);
        console.log('Description added');
      } catch (descErr) {
        console.error('Description error (non-critical):', descErr.toString());
      }
    }

    // 質問追加
    if (template.questions && template.questions.length > 0) {
      console.log('Adding questions:', template.questions.length);
      for (let i = 0; i < template.questions.length; i++) {
        try {
          addQuestionSafely(form, template.questions[i]);
          console.log('Added question', i + 1);
        } catch (qErr) {
          console.error('Question error (non-critical):', qErr.toString());
        }
      }
    }

    // 共有設定 - 最も重要な部分
    console.log('Starting permission settings...');

    // DriveAppを使用して権限設定
    try {
      const file = DriveApp.getFileById(formId);
      console.log('Got file reference');

      // リンク共有を有効化（誰でも編集可能）
      try {
        file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.EDIT);
        response.linkSharingEnabled = true;
        response.sharingMode = 'anyone_with_link_can_edit';
        console.log('✅ Link sharing enabled - Anyone with link can edit');
      } catch (shareErr) {
        console.error('Link sharing error:', shareErr.toString());
        // 代替: ANYONE → DOMAIN
        try {
          file.setSharing(DriveApp.Access.DOMAIN_WITH_LINK, DriveApp.Permission.EDIT);
          response.linkSharingEnabled = true;
          response.sharingMode = 'domain_with_link_can_edit';
          console.log('✅ Domain sharing enabled');
        } catch (domainErr) {
          console.error('Domain sharing also failed:', domainErr.toString());
        }
      }

      // 特定ユーザーに編集権限を付与
      const emailsToAdd = [];

      // 優先順位: userEmail > firebaseEmail
      if (data.userEmail && data.userEmail.includes('@')) {
        emailsToAdd.push(data.userEmail);
      }

      if (data.firebaseEmail && data.firebaseEmail.includes('@') &&
          data.firebaseEmail !== data.userEmail) {
        emailsToAdd.push(data.firebaseEmail);
      }

      console.log('Attempting to add editors:', emailsToAdd.join(', '));

      for (const email of emailsToAdd) {
        try {
          console.log('Adding editor:', email);
          file.addEditor(email);
          response.editorsAdded.push(email);
          response.editorAdded = true;
          console.log('✅ Successfully added editor:', email);

          // 最初に成功したメールアドレスを記録
          if (!response.sharedWith) {
            response.sharedWith = email;
          }
        } catch (addErr) {
          console.error('Failed to add editor', email, ':', addErr.toString());
          response.editorsFailed.push({
            email: email,
            error: addErr.toString()
          });
        }
      }

      // 権限の確認
      try {
        const editors = file.getEditors();
        console.log('Current editors count:', editors.length);
        for (const editor of editors) {
          const editorEmail = editor.getEmail();
          if (editorEmail) {
            console.log('Confirmed editor:', editorEmail);
          }
        }
      } catch (checkErr) {
        console.error('Could not check editors:', checkErr.toString());
      }

    } catch (driveErr) {
      console.error('Drive operations error:', driveErr.toString());
      response.message = 'ドライブ操作エラー: ' + driveErr.toString();
    }

    // 最終的なメッセージ設定
    if (response.editorAdded || response.linkSharingEnabled) {
      response.success = true;
      if (response.linkSharingEnabled) {
        response.message = 'フォームが作成されました（リンクを知っている全員が編集可能）';
      } else if (response.editorAdded) {
        response.message = 'フォームが作成され、編集権限が設定されました';
      }
    } else {
      response.success = true; // フォームは作成されたので部分的成功
      response.message = 'フォームは作成されましたが、編集権限の自動設定に失敗しました。手動で共有設定してください。';
    }

    console.log('=== FINAL RESPONSE ===');
    console.log(JSON.stringify(response));

    return ContentService.createTextOutput(JSON.stringify(response))
      .setMimeType(ContentService.MimeType.JSON);

  } catch (error) {
    console.error('=== CRITICAL ERROR ===');
    console.error(error.toString());
    console.error('Stack:', error.stack);

    response.success = false;
    response.message = 'エラー: ' + error.toString();
    response.error = error.toString();

    return ContentService.createTextOutput(JSON.stringify(response))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

// 質問を安全に追加
function addQuestionSafely(form, question) {
  if (!question || !question.question) return;

  let item;
  const type = question.type || 'shortText';

  try {
    switch (type) {
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
        item = form.addTextItem();
        item.setTitle(question.question);
    }

    if (item) {
      if (question.required === true) {
        item.setRequired(true);
      }
      if (question.placeholder) {
        item.setHelpText(question.placeholder);
      }
    }
  } catch (err) {
    console.error('Question creation error:', err.toString());
  }
}

// GETリクエスト対応（動作確認用）
function doGet(e) {
  return ContentService.createTextOutput(JSON.stringify({
    success: true,
    message: 'Google Forms API Final Version is ready',
    version: '4.0',
    features: [
      'Automatic form creation',
      'Link sharing (anyone can edit)',
      'Specific user permissions',
      'Error resilience',
      'Complete response guaranteed'
    ],
    timestamp: new Date().toISOString()
  })).setMimeType(ContentService.MimeType.JSON);
}

// テスト関数（Google Apps Script エディタで実行）
function testDirectly() {
  console.log('=== DIRECT TEST START ===');

  // テスト用のリクエスト
  const mockRequest = {
    postData: {
      contents: JSON.stringify({
        action: 'createForm',
        userEmail: 'yudai71015@gmail.com',
        firebaseEmail: 'yudai5287@ruri.waseda.jp',
        customTitle: 'Direct Test ' + new Date().getTime(),
        template: {
          title: 'Test Form',
          description: 'This is a test',
          questions: [
            {
              question: 'Your name',
              type: 'shortText',
              required: true
            }
          ]
        }
      })
    }
  };

  const result = doPost(mockRequest);
  const content = result.getContent();
  console.log('Result:', content);

  const response = JSON.parse(content);

  console.log('\n=== TEST RESULTS ===');
  console.log('✅ Success:', response.success);
  console.log('📝 Form ID:', response.formId);
  console.log('👤 Editor Added:', response.editorAdded);
  console.log('🔗 Sharing Mode:', response.sharingMode);
  console.log('💬 Message:', response.message);

  if (response.formId) {
    console.log('\n📋 Form URL:', response.editUrl);
  }

  console.log('=== TEST END ===');
}