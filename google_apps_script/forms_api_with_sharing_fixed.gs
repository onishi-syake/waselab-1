// Google Apps Script - Forms API Web App with Sharing (修正版)
// 編集権限付与の問題を解決

function doPost(e) {
  try {
    console.log('=== doPost START ===');
    console.log('Raw post data:', e.postData.contents);

    const data = JSON.parse(e.postData.contents);
    console.log('Action:', data.action);
    console.log('UserEmail:', data.userEmail);
    console.log('FirebaseEmail:', data.firebaseEmail);

    if (data.action === 'createForm') {
      const result = createFormFromTemplate(data);
      console.log('=== doPost END - Returning result ===');
      return result;
    }

    return ContentService.createTextOutput(JSON.stringify({
      success: false,
      error: 'Invalid action: ' + data.action
    })).setMimeType(ContentService.MimeType.JSON);

  } catch (error) {
    console.error('doPost error:', error.toString());
    return ContentService.createTextOutput(JSON.stringify({
      success: false,
      error: error.toString(),
      stage: 'doPost'
    })).setMimeType(ContentService.MimeType.JSON);
  }
}

function createFormFromTemplate(data) {
  // すべての変数を最初に宣言
  let form = null;
  let formId = '';
  let formUrl = '';
  let editUrl = '';
  let userEditUrl = '';
  let sharingSet = false;
  let editorAdded = false;
  const editorsAdded = [];
  const editorsFailed = [];
  let currentStage = 'init';

  try {
    console.log('=== createFormFromTemplate START ===');

    // データ取得
    const template = data.template;
    const customTitle = data.customTitle || template.title;
    const userEmail = data.userEmail || null;
    const firebaseEmail = data.firebaseEmail || null;

    console.log('Title:', customTitle);
    console.log('UserEmail:', userEmail);
    console.log('FirebaseEmail:', firebaseEmail);

    // ステージ1: フォーム作成
    currentStage = 'create_form';
    console.log('Stage 1: Creating form...');
    form = FormApp.create(customTitle);
    formId = form.getId();
    formUrl = form.getPublishedUrl();
    editUrl = form.getEditUrl();
    console.log('Form created with ID:', formId);

    // ステージ2: フォーム設定
    currentStage = 'form_settings';
    console.log('Stage 2: Configuring form settings...');

    // 説明を設定
    if (template.description || template.instructions) {
      const fullDescription = [
        template.description,
        template.instructions
      ].filter(Boolean).join('\n\n');
      form.setDescription(fullDescription);
    }

    // 質問を追加
    if (template.questions && template.questions.length > 0) {
      console.log('Adding', template.questions.length, 'questions...');
      template.questions.forEach((q, i) => {
        try {
          addQuestionToForm(form, q);
        } catch (qErr) {
          console.error('Failed to add question', i, ':', qErr.toString());
        }
      });
    }

    // フォームの基本設定
    form.setRequireLogin(false);
    form.setCollectEmail(true);
    form.setLimitOneResponsePerUser(false);
    form.setShowLinkToRespondAgain(true);

    // ステージ3: 共有設定
    currentStage = 'sharing_settings';
    console.log('Stage 3: Setting sharing permissions...');

    try {
      const formFile = DriveApp.getFileById(formId);

      // リンク共有を設定
      try {
        formFile.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.EDIT);
        sharingSet = true;
        console.log('Link sharing enabled: Anyone with link can edit');
      } catch (shareErr) {
        console.error('Could not enable link sharing:', shareErr.toString());
      }

      // ユーザーを編集者として追加
      const emailsToAdd = [];

      if (userEmail && userEmail.includes('@')) {
        emailsToAdd.push(userEmail);
      }

      if (firebaseEmail && firebaseEmail.includes('@') && firebaseEmail !== userEmail) {
        emailsToAdd.push(firebaseEmail);
      }

      console.log('Emails to add as editors:', emailsToAdd.join(', '));

      for (const email of emailsToAdd) {
        try {
          formFile.addEditor(email);
          editorsAdded.push(email);
          editorAdded = true;
          console.log('Successfully added editor:', email);

          // 確認
          const editors = formFile.getEditors();
          const found = editors.some(e => e.getEmail()?.toLowerCase() === email.toLowerCase());
          console.log('Editor confirmed:', email, found);

        } catch (edErr) {
          console.error('Failed to add editor', email, ':', edErr.toString());
          editorsFailed.push({email: email, error: edErr.toString()});
        }
      }

      // URLを生成
      userEditUrl = editUrl;
      if (emailsToAdd.length > 0) {
        const targetEmail = emailsToAdd[0];
        try {
          const urlObj = new URL(editUrl);
          urlObj.searchParams.set('authuser', '0');
          urlObj.searchParams.set('login_hint', targetEmail);
          userEditUrl = urlObj.toString();
          console.log('Generated custom edit URL for:', targetEmail);
        } catch (urlErr) {
          console.error('URL generation error:', urlErr.toString());
        }
      }

    } catch (fileErr) {
      console.error('File operations error:', fileErr.toString());
      currentStage = 'file_error';
    }

    // ステージ4: レスポンス作成
    currentStage = 'create_response';
    console.log('Stage 4: Creating response...');

    const response = {
      success: true,
      formId: formId,
      formUrl: formUrl,
      editUrl: userEditUrl || editUrl,
      directEditUrl: editUrl,
      sharedWith: editorsAdded.length > 0 ? editorsAdded[0] : null,
      editorAdded: editorAdded,
      editorsAdded: editorsAdded,
      editorsFailed: editorsFailed,
      sharingMode: sharingSet ? 'anyone_with_link_can_edit' : 'restricted',
      linkSharingEnabled: sharingSet,
      timestamp: new Date().toISOString(),
      message: (editorAdded || sharingSet)
        ? 'フォームが作成され、編集権限が設定されました'
        : 'フォームは作成されましたが、編集権限の設定に失敗しました',
      instruction: 'フォームを開く際は、' + (userEmail || firebaseEmail || '連携した') + ' Googleアカウントでログインしてください'
    };

    console.log('=== FINAL RESPONSE ===');
    console.log(JSON.stringify(response));
    console.log('=== createFormFromTemplate END ===');

    return ContentService.createTextOutput(JSON.stringify(response))
      .setMimeType(ContentService.MimeType.JSON);

  } catch (error) {
    console.error('ERROR at stage:', currentStage);
    console.error('Error:', error.toString());
    console.error('Stack:', error.stack);

    // フォームが作成されていれば部分的成功として返す
    if (formId) {
      const partialResponse = {
        success: true,
        formId: formId,
        formUrl: formUrl || '',
        editUrl: editUrl || '',
        directEditUrl: editUrl || '',
        sharedWith: null,
        editorAdded: false,
        editorsAdded: [],
        editorsFailed: [],
        sharingMode: 'unknown',
        linkSharingEnabled: false,
        timestamp: new Date().toISOString(),
        message: 'フォームは作成されましたが、エラーが発生しました: ' + error.toString(),
        error: error.toString(),
        errorStage: currentStage
      };

      console.log('Returning partial success response');
      return ContentService.createTextOutput(JSON.stringify(partialResponse))
        .setMimeType(ContentService.MimeType.JSON);
    }

    // 完全に失敗
    return ContentService.createTextOutput(JSON.stringify({
      success: false,
      error: error.toString(),
      stage: currentStage,
      timestamp: new Date().toISOString()
    })).setMimeType(ContentService.MimeType.JSON);
  }
}

function addQuestionToForm(form, question) {
  let item;

  switch (question.type) {
    case 'multipleChoice':
      item = form.addMultipleChoiceItem();
      item.setTitle(question.question);
      if (question.options) {
        item.setChoiceValues(question.options);
      }
      break;

    case 'checkbox':
      item = form.addCheckboxItem();
      item.setTitle(question.question);
      if (question.options) {
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
      item = form.addTextItem();
      item.setTitle(question.question);
  }

  // 必須設定
  if (item && question.required) {
    item.setRequired(true);
  }

  // ヘルプテキスト設定
  if (item && question.placeholder) {
    item.setHelpText(question.placeholder);
  }
}

// テスト用
function doGet(e) {
  return ContentService.createTextOutput(JSON.stringify({
    success: true,
    message: 'Google Forms API is ready',
    version: '2.0'
  })).setMimeType(ContentService.MimeType.JSON);
}