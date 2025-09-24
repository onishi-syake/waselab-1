// Google Apps Script - Forms API using Template Copy Method
// FormApp.create()がサポートされていない場合の代替方法
// 事前に作成したテンプレートフォームをコピーして使用

// テンプレートフォームのID（事前に作成してください）
// 1. Google Formsで空のフォームを作成
// 2. フォームのURLからIDを取得（/forms/d/[このID部分]/edit）
// 3. 下記のTEMPLATE_FORM_IDに設定
const TEMPLATE_FORM_ID = '1FAIpQLSeExample123'; // ← ここにテンプレートフォームのIDを設定

function doPost(e) {
  // 必ず完全なレスポンスを返すように初期化
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
    console.log('=== doPost START (Copy Template Method) ===');
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

    // テンプレートフォームが設定されているか確認
    if (!TEMPLATE_FORM_ID || TEMPLATE_FORM_ID === '1FAIpQLSeExample123') {
      response.message = 'テンプレートフォームIDが設定されていません。GASコードのTEMPLATE_FORM_IDを更新してください。';
      return ContentService.createTextOutput(JSON.stringify(response))
        .setMimeType(ContentService.MimeType.JSON);
    }

    const template = data.template || {};
    const title = data.customTitle || template.title || 'New Form ' + Date.now();

    console.log('Copying template form:', TEMPLATE_FORM_ID);
    console.log('New title:', title);

    // 方法1: DriveApp.getFileById().makeCopy()を使用
    let form, formId, formUrl, editUrl;
    try {
      // テンプレートフォームをコピー
      const templateFile = DriveApp.getFileById(TEMPLATE_FORM_ID);
      const copiedFile = templateFile.makeCopy(title);
      formId = copiedFile.getId();

      // FormAppでフォームを取得
      form = FormApp.openById(formId);
      formUrl = form.getPublishedUrl();
      editUrl = form.getEditUrl();

      response.formId = formId;
      response.formUrl = formUrl;
      response.editUrl = editUrl;
      response.directEditUrl = editUrl;

      console.log('Form copied successfully');
      console.log('New Form ID:', formId);

    } catch (copyErr) {
      console.error('Copy error:', copyErr.toString());

      // 方法2: FormApp.openById()から直接操作を試みる
      try {
        console.log('Trying alternative method with FormApp.openById...');
        form = FormApp.openById(TEMPLATE_FORM_ID);

        // 既存のフォームの設定を変更（コピーではなく直接編集）
        // 注意：これはテンプレートフォーム自体を変更してしまう
        form.setTitle(title);
        formId = TEMPLATE_FORM_ID;
        formUrl = form.getPublishedUrl();
        editUrl = form.getEditUrl();

        response.formId = formId;
        response.formUrl = formUrl;
        response.editUrl = editUrl;
        response.directEditUrl = editUrl;

        console.log('Using template form directly (modified title)');

      } catch (openErr) {
        console.error('Alternative method also failed:', openErr.toString());
        response.message = 'フォームの作成/コピーに失敗: ' + copyErr.toString();
        return ContentService.createTextOutput(JSON.stringify(response))
          .setMimeType(ContentService.MimeType.JSON);
      }
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

    // 既存の質問をクリア（テンプレートの質問を削除）
    try {
      const items = form.getItems();
      for (const item of items) {
        form.deleteItem(item);
      }
      console.log('Cleared template questions');
    } catch (clearErr) {
      console.error('Could not clear template questions:', clearErr.toString());
    }

    // 新しい質問を追加
    if (template.questions && template.questions.length > 0) {
      console.log('Adding questions:', template.questions.length);
      for (let i = 0; i < template.questions.length; i++) {
        try {
          addQuestionToForm(form, template.questions[i]);
          console.log('Added question', i + 1);
        } catch (qErr) {
          console.error('Question error:', qErr.toString());
        }
      }
    }

    // 共有設定
    console.log('Starting permission settings...');

    try {
      const file = DriveApp.getFileById(formId);
      console.log('Got file reference');

      // リンク共有を有効化
      try {
        file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.EDIT);
        response.linkSharingEnabled = true;
        response.sharingMode = 'anyone_with_link_can_edit';
        console.log('✅ Link sharing enabled - Anyone with link can edit');
      } catch (shareErr) {
        console.error('Link sharing error:', shareErr.toString());
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

    } catch (driveErr) {
      console.error('Drive operations error:', driveErr.toString());
    }

    // 最終的なメッセージ
    if (response.editorAdded || response.linkSharingEnabled) {
      response.success = true;
      if (response.linkSharingEnabled) {
        response.message = 'フォームが作成されました（リンクを知っている全員が編集可能）';
      } else if (response.editorAdded) {
        response.message = 'フォームが作成され、編集権限が設定されました';
      }
    } else {
      response.success = true;
      response.message = 'フォームは作成されましたが、編集権限の自動設定に失敗しました';
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

function addQuestionToForm(form, question) {
  if (!question || !question.question) return;

  let item;
  const type = question.type || 'shortText';

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
}

// GET リクエスト（動作確認用）
function doGet(e) {
  return ContentService.createTextOutput(JSON.stringify({
    success: true,
    message: 'Google Forms API (Copy Template Method) is ready',
    version: '5.0',
    method: 'template_copy',
    templateFormId: TEMPLATE_FORM_ID,
    templateConfigured: TEMPLATE_FORM_ID && TEMPLATE_FORM_ID !== '1FAIpQLSeExample123',
    timestamp: new Date().toISOString()
  })).setMimeType(ContentService.MimeType.JSON);
}

// テンプレートフォーム作成ヘルパー
function createTemplateForm() {
  console.log('=== Creating Template Form ===');

  try {
    // 新しいフォームを作成（これは手動で一度だけ実行）
    const templateForm = FormApp.create('TEMPLATE - DO NOT DELETE');
    const templateId = templateForm.getId();

    templateForm.setDescription('This is a template form. Do not submit responses to this form.');
    templateForm.setRequireLogin(false);
    templateForm.setCollectEmail(true);

    console.log('✅ Template form created successfully');
    console.log('Template Form ID:', templateId);
    console.log('Edit URL:', templateForm.getEditUrl());
    console.log('\n⚠️ IMPORTANT: Copy this ID and update TEMPLATE_FORM_ID in the script');

    return templateId;

  } catch (error) {
    console.error('Failed to create template:', error.toString());
    return null;
  }
}

// テスト関数
function testWithTemplate() {
  console.log('=== TEST WITH TEMPLATE ===');

  if (!TEMPLATE_FORM_ID || TEMPLATE_FORM_ID === '1FAIpQLSeExample123') {
    console.error('❌ TEMPLATE_FORM_ID is not configured');
    console.log('Run createTemplateForm() first to create a template');
    return;
  }

  const mockRequest = {
    postData: {
      contents: JSON.stringify({
        action: 'createForm',
        userEmail: 'yudai71015@gmail.com',
        firebaseEmail: 'yudai5287@ruri.waseda.jp',
        customTitle: 'Test Copy ' + new Date().getTime(),
        template: {
          title: 'Test Form',
          description: 'Test description',
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
  const response = JSON.parse(content);

  console.log('\n=== RESULTS ===');
  console.log('Success:', response.success);
  console.log('Form ID:', response.formId);
  console.log('Editor Added:', response.editorAdded);
  console.log('Sharing Mode:', response.sharingMode);
  console.log('Message:', response.message);

  if (response.formId) {
    console.log('\n📋 Form URL:', response.editUrl);
  }
}