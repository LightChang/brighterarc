# SEO + AEO 優化規則庫

## 概述

本規則庫定義所有 SEO（搜尋引擎優化）和 AEO（AI 答案引擎優化）的標準與範本。Writer 和 Reviewer 模組都必須參照此檔案執行任務。

---

## 一、JSON-LD Schema 類型定義

### 必填 Schema（7 種 + 1 內嵌）

> **注意**：WebSite Schema 透過 Article.isPartOf 內嵌，包含 SearchAction 網站搜尋功能。

#### 1. WebPage + Speakable

```json
{
  "@type": "WebPage",
  "@id": "{{CANONICAL_URL}}#webpage",
  "url": "{{CANONICAL_URL}}",
  "name": "{{TITLE}}",
  "description": "{{META_DESCRIPTION}}",
  "inLanguage": "zh-TW",
  "isPartOf": { "@id": "{{SITE_URL}}#website" },
  "primaryImageOfPage": { "@type": "ImageObject", "url": "{{OG_IMAGE}}" },
  "datePublished": "{{PUBLISHED_DATE}}",
  "dateModified": "{{MODIFIED_DATE}}",
  "speakable": {
    "@type": "SpeakableSpecification",
    "cssSelector": [
      ".article-summary",
      ".speakable-content",
      ".key-takeaway",
      ".key-answer",
      ".expert-quote",
      ".actionable-steps li",
      ".faq-answer-content"
    ]
  }
}
```

**必填欄位**：
- `@id`：必須使用 `{{CANONICAL_URL}}#webpage` 格式
- `speakable.cssSelector`：必須包含至少 7 個選擇器（見上方範例）

---

#### 2. Article（完整版）

```json
{
  "@type": "Article",
  "@id": "{{CANONICAL_URL}}#article",
  "mainEntityOfPage": {
    "@id": "{{CANONICAL_URL}}#webpage",
    "significantLink": ["{{RELATED_ARTICLE_1}}", "{{RELATED_ARTICLE_2}}"]
  },
  "headline": "{{TITLE}}",
  "alternativeHeadline": "{{TITLE_EN}}",
  "description": "{{META_DESCRIPTION}}",
  "image": { "@type": "ImageObject", "url": "{{OG_IMAGE}}", "width": 1200, "height": 630 },
  "author": { "@id": "{{AUTHOR_PROFILE_URL}}#person" },
  "publisher": { "@id": "{{SITE_URL}}#organization" },
  "datePublished": "{{PUBLISHED_DATE}}",
  "dateModified": "{{MODIFIED_DATE}}",
  "articleSection": "{{ARTICLE_SECTION}}",
  "keywords": "{{META_KEYWORDS}}",
  "wordCount": "{{WORD_COUNT}}",
  "inLanguage": "zh-TW",
  "isAccessibleForFree": true,
  "isPartOf": {
    "@type": "WebSite",
    "@id": "{{SITE_URL}}#website",
    "name": "{{SITE_NAME}}",
    "potentialAction": {
      "@type": "SearchAction",
      "target": "{{SITE_URL}}/search?q={search_term}",
      "query-input": "required name=search_term"
    }
  }
}
```

**必填欄位**：
- `author`：必須連結到 Person Schema
- `publisher`：必須連結到 Organization Schema
- `isAccessibleForFree`：必須為 `true`
- `isPartOf`：必須包含 SearchAction
- `mainEntityOfPage.significantLink`：相關文章連結（至少 2 個）

---

#### 3. Person（E-E-A-T 作者資訊）

```json
{
  "@type": "Person",
  "@id": "{{AUTHOR_PROFILE_URL}}#person",
  "name": "{{AUTHOR_NAME}}",
  "url": "{{AUTHOR_PROFILE_URL}}",
  "image": "{{AUTHOR_IMAGE}}",
  "jobTitle": "{{AUTHOR_POSITION}}",
  "worksFor": { "@type": "Organization", "name": "{{AUTHOR_COMPANY}}" },
  "description": "{{AUTHOR_BIO}}",
  "sameAs": ["{{SOCIAL_LINK_1}}", "{{SOCIAL_LINK_2}}"],
  "knowsAbout": ["{{EXPERTISE_1}}", "{{EXPERTISE_2}}", "{{EXPERTISE_3}}"],
  "hasCredential": [
    {
      "@type": "EducationalOccupationalCredential",
      "name": "{{CREDENTIAL_NAME}}",
      "credentialCategory": "{{CREDENTIAL_CATEGORY}}"
    }
  ],
  "alumniOf": {
    "@type": "Organization",
    "name": "{{EDUCATION_OR_EXPERIENCE}}"
  }
}
```

**E-E-A-T 必填欄位**：
- `knowsAbout`：至少 2 個專長領域
- `hasCredential`：至少 1 個認證/資格
- `sameAs`：至少 1 個社群連結

---

#### 4. Organization（出版者資訊）

```json
{
  "@type": "Organization",
  "@id": "{{SITE_URL}}#organization",
  "name": "{{PUBLISHER_NAME}}",
  "url": "{{SITE_URL}}",
  "logo": { "@type": "ImageObject", "url": "{{PUBLISHER_LOGO}}", "width": 600, "height": 60 },
  "sameAs": ["{{PUBLISHER_FACEBOOK}}", "{{PUBLISHER_INSTAGRAM}}", "{{PUBLISHER_YOUTUBE}}"],
  "contactPoint": {
    "@type": "ContactPoint",
    "contactType": "customer service",
    "telephone": "{{PUBLISHER_PHONE}}",
    "email": "{{PUBLISHER_EMAIL}}"
  }
}
```

**必填欄位**：
- `logo`：必須包含 width/height
- `contactPoint`：必須包含 telephone 或 email

---

#### 5. BreadcrumbList（麵包屑導航）

```json
{
  "@type": "BreadcrumbList",
  "itemListElement": [
    { "@type": "ListItem", "position": 1, "name": "首頁", "item": "{{SITE_URL}}" },
    { "@type": "ListItem", "position": 2, "name": "{{CATEGORY}}", "item": "{{CATEGORY_URL}}" },
    { "@type": "ListItem", "position": 3, "name": "{{TITLE}}", "item": "{{CANONICAL_URL}}" }
  ]
}
```

**規則**：
- 至少 2 層（首頁 + 文章）
- position 必須從 1 開始連續編號

---

#### 6. FAQPage（常見問題）

```json
{
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "{{QUESTION_1}}",
      "acceptedAnswer": { "@type": "Answer", "text": "{{ANSWER_1}}" }
    },
    {
      "@type": "Question",
      "name": "{{QUESTION_2}}",
      "acceptedAnswer": { "@type": "Answer", "text": "{{ANSWER_2}}" }
    }
  ]
}
```

**規則**：
- 必須包含 3-5 個 Q&A
- 問題必須與文章內容相關
- 答案必須完整、可被獨立理解

---

#### 7. ImageObject（主圖）

```json
{
  "@type": "ImageObject",
  "@id": "{{CANONICAL_URL}}#primaryimage",
  "url": "{{OG_IMAGE}}",
  "width": 1200,
  "height": 630,
  "caption": "{{OG_IMAGE_ALT}}",
  "representativeOfPage": true,
  "license": "{{IMAGE_LICENSE_URL}}",
  "acquireLicensePage": "{{SITE_URL}}/license",
  "creditText": "{{IMAGE_CREDIT}}"
}
```

**必填欄位**：
- `license`：圖片授權 URL
- `creditText`：圖片來源標示

---

### 條件式 Schema（5 種）

#### 8. HowTo（步驟教學 - 若有操作步驟）

```json
{
  "@type": "HowTo",
  "@id": "{{CANONICAL_URL}}#howto",
  "name": "{{HOWTO_NAME}}",
  "description": "{{HOWTO_DESCRIPTION}}",
  "totalTime": "PT{{TOTAL_MINUTES}}M",
  "step": [
    {
      "@type": "HowToStep",
      "position": 1,
      "name": "{{STEP_1_NAME}}",
      "text": "{{STEP_1_TEXT}}",
      "image": "{{STEP_1_IMAGE}}"
    }
  ]
}
```

**適用條件**：文章包含可執行的步驟流程

---

#### 9. VideoObject（影片 - 若有嵌入影片）

```json
{
  "@type": "VideoObject",
  "@id": "{{CANONICAL_URL}}#video",
  "name": "{{VIDEO_TITLE}}",
  "description": "{{VIDEO_DESCRIPTION}}",
  "thumbnailUrl": "{{VIDEO_THUMBNAIL}}",
  "uploadDate": "{{PUBLISHED_DATE}}",
  "duration": "PT{{VIDEO_MINUTES}}M{{VIDEO_SECONDS}}S",
  "contentUrl": "{{VIDEO_URL}}",
  "embedUrl": "{{VIDEO_EMBED_URL}}"
}
```

**必填欄位**：
- `duration`：ISO 8601 格式（如 PT5M30S）
- `thumbnailUrl`：影片縮圖

---

#### 10. ItemList（列表 - 競爭 Featured Snippet）

```json
{
  "@type": "ItemList",
  "@id": "{{CANONICAL_URL}}#itemlist",
  "name": "{{LIST_TITLE}}",
  "description": "{{LIST_DESCRIPTION}}",
  "numberOfItems": {{ITEM_COUNT}},
  "itemListElement": [
    {
      "@type": "ListItem",
      "position": 1,
      "name": "{{ITEM_1_NAME}}",
      "description": "{{ITEM_1_DESCRIPTION}}"
    }
  ]
}
```

**適用條件**：文章包含排序清單（如「5 大方法」）

---

#### 11. Table（比較表格）

```json
{
  "@type": "Table",
  "@id": "{{CANONICAL_URL}}#table",
  "about": "{{TABLE_SUBJECT}}",
  "description": "{{TABLE_DESCRIPTION}}"
}
```

**適用條件**：文章包含比較表格

---

#### 12. Recipe（食譜 - 料理類文章）

```json
{
  "@type": "Recipe",
  "@id": "{{CANONICAL_URL}}#recipe-1",
  "name": "{{RECIPE_NAME}}",
  "image": ["{{RECIPE_IMAGE}}"],
  "author": { "@id": "{{AUTHOR_PROFILE_URL}}#person" },
  "datePublished": "{{PUBLISHED_DATE}}",
  "description": "{{RECIPE_DESCRIPTION}}",
  "prepTime": "PT{{PREP_MINUTES}}M",
  "cookTime": "PT{{COOK_MINUTES}}M",
  "totalTime": "PT{{TOTAL_MINUTES}}M",
  "recipeYield": "{{SERVINGS}}",
  "recipeCategory": "{{RECIPE_CATEGORY}}",
  "recipeCuisine": "{{CUISINE_TYPE}}",
  "keywords": "{{RECIPE_KEYWORDS}}",
  "recipeIngredient": [
    "{{INGREDIENT_1}}",
    "{{INGREDIENT_2}}"
  ],
  "recipeInstructions": [
    {
      "@type": "HowToStep",
      "name": "{{STEP_1_NAME}}",
      "text": "{{STEP_1_TEXT}}"
    }
  ],
  "nutrition": {
    "@type": "NutritionInformation",
    "calories": "{{CALORIES}} calories",
    "proteinContent": "{{PROTEIN}}g",
    "fatContent": "{{FAT}}g",
    "carbohydrateContent": "{{CARBS}}g",
    "fiberContent": "{{FIBER}}g"
  },
  "suitableForDiet": "https://schema.org/{{DIET_TYPE}}"
}
```

**必填欄位**：
- `recipeIngredient`：完整食材清單（含份量）
- `recipeInstructions`：詳細步驟（使用 HowToStep）
- `prepTime` / `cookTime` / `totalTime`：ISO 8601 格式

**建議選填欄位**：
- `nutrition`：營養資訊（熱量、蛋白質、脂肪、碳水、膳食纖維）
- `suitableForDiet`：適合的飲食類型（如 LowFatDiet、VeganDiet）
- `recipeCategory`：分類（如「主菜」「湯品」「甜點」）
- `recipeCuisine`：菜系（如「台式料理」「地中海料理」）

**人格專屬規則**：
- **P3-AI爸氣主廚**：文章必須包含 2-3 道食譜，每道都需完整的 Recipe Schema

---

### 進階條件式 Schema（5 種）

> 以下 Schema 依據頁面內容動態判斷是否需要加入。

#### 13. Review + AggregateRating（評價 - 若有產品/服務評論）

**判斷條件**：
- 頁面包含星級評分（★★★★☆）
- 頁面有多則用戶評論/心得
- 頁面為產品開箱、服務體驗文

```json
{
  "@type": "Review",
  "@id": "{{CANONICAL_URL}}#review",
  "itemReviewed": {
    "@type": "{{REVIEWED_ITEM_TYPE}}",
    "name": "{{REVIEWED_ITEM_NAME}}",
    "image": "{{REVIEWED_ITEM_IMAGE}}"
  },
  "reviewRating": {
    "@type": "Rating",
    "ratingValue": "{{RATING_VALUE}}",
    "bestRating": "5",
    "worstRating": "1"
  },
  "author": { "@id": "{{AUTHOR_PROFILE_URL}}#person" },
  "datePublished": "{{PUBLISHED_DATE}}",
  "reviewBody": "{{REVIEW_SUMMARY}}"
}
```

**AggregateRating（多則評論彙整）**：

```json
{
  "@type": "AggregateRating",
  "itemReviewed": {
    "@type": "{{REVIEWED_ITEM_TYPE}}",
    "name": "{{REVIEWED_ITEM_NAME}}"
  },
  "ratingValue": "{{AVG_RATING}}",
  "bestRating": "5",
  "ratingCount": "{{TOTAL_RATINGS}}",
  "reviewCount": "{{TOTAL_REVIEWS}}"
}
```

**`REVIEWED_ITEM_TYPE` 可選值**：
- `Product`：產品評測
- `Service`：服務評價
- `Book`：書評
- `Movie`：影評
- `Restaurant`：餐廳評價
- `SoftwareApplication`：App/軟體評測

---

#### 14. Event（活動 - 若有活動/講座/課程資訊）

**判斷條件**：
- 頁面包含活動日期、時間、地點
- 頁面有報名連結或票價資訊
- 內容類型為講座、工作坊、展覽、線下活動

```json
{
  "@type": "Event",
  "@id": "{{CANONICAL_URL}}#event",
  "name": "{{EVENT_NAME}}",
  "description": "{{EVENT_DESCRIPTION}}",
  "image": "{{EVENT_IMAGE}}",
  "startDate": "{{EVENT_START_DATE}}",
  "endDate": "{{EVENT_END_DATE}}",
  "eventStatus": "https://schema.org/EventScheduled",
  "eventAttendanceMode": "https://schema.org/{{ATTENDANCE_MODE}}",
  "location": {
    "@type": "{{LOCATION_TYPE}}",
    "name": "{{LOCATION_NAME}}",
    "address": {
      "@type": "PostalAddress",
      "streetAddress": "{{STREET_ADDRESS}}",
      "addressLocality": "{{CITY}}",
      "addressRegion": "{{REGION}}",
      "postalCode": "{{POSTAL_CODE}}",
      "addressCountry": "TW"
    }
  },
  "organizer": {
    "@type": "Organization",
    "name": "{{ORGANIZER_NAME}}",
    "url": "{{ORGANIZER_URL}}"
  },
  "performer": {
    "@type": "Person",
    "name": "{{PERFORMER_NAME}}"
  },
  "offers": {
    "@type": "Offer",
    "url": "{{TICKET_URL}}",
    "price": "{{TICKET_PRICE}}",
    "priceCurrency": "TWD",
    "availability": "https://schema.org/InStock",
    "validFrom": "{{SALE_START_DATE}}"
  }
}
```

**`ATTENDANCE_MODE` 可選值**：
- `OfflineEventAttendanceMode`：實體活動
- `OnlineEventAttendanceMode`：線上活動
- `MixedEventAttendanceMode`：混合活動

**`LOCATION_TYPE` 可選值**：
- `Place`：實體場地
- `VirtualLocation`：線上（需用 `url` 取代 `address`）

---

#### 15. Course（課程 - 若為線上課程內容）

**判斷條件**：
- 頁面為線上課程介紹
- 包含課程大綱、時數、講師資訊
- 有價格或報名資訊

```json
{
  "@type": "Course",
  "@id": "{{CANONICAL_URL}}#course",
  "name": "{{COURSE_NAME}}",
  "description": "{{COURSE_DESCRIPTION}}",
  "provider": {
    "@type": "Organization",
    "name": "{{PROVIDER_NAME}}",
    "url": "{{PROVIDER_URL}}"
  },
  "instructor": {
    "@type": "Person",
    "name": "{{INSTRUCTOR_NAME}}",
    "description": "{{INSTRUCTOR_BIO}}"
  },
  "educationalLevel": "{{EDUCATION_LEVEL}}",
  "teaches": ["{{SKILL_1}}", "{{SKILL_2}}", "{{SKILL_3}}"],
  "inLanguage": "zh-TW",
  "coursePrerequisites": "{{PREREQUISITES}}",
  "hasCourseInstance": {
    "@type": "CourseInstance",
    "courseMode": "{{COURSE_MODE}}",
    "courseWorkload": "PT{{TOTAL_HOURS}}H",
    "instructor": { "@id": "{{INSTRUCTOR_URL}}#person" }
  },
  "offers": {
    "@type": "Offer",
    "price": "{{COURSE_PRICE}}",
    "priceCurrency": "TWD",
    "availability": "https://schema.org/InStock",
    "url": "{{ENROLLMENT_URL}}"
  },
  "aggregateRating": {
    "@type": "AggregateRating",
    "ratingValue": "{{AVG_RATING}}",
    "ratingCount": "{{RATING_COUNT}}",
    "reviewCount": "{{REVIEW_COUNT}}"
  }
}
```

**`COURSE_MODE` 可選值**：
- `online`：純線上
- `onsite`：純實體
- `blended`：混合式

**`EDUCATION_LEVEL` 建議值**：
- `Beginner`：初學者
- `Intermediate`：中階
- `Advanced`：進階

---

#### 16. Product（產品 - 若為商品頁面）

**判斷條件**：
- 頁面為產品介紹或銷售頁
- 包含價格、庫存、規格資訊
- 有購買按鈕或加入購物車功能

```json
{
  "@type": "Product",
  "@id": "{{CANONICAL_URL}}#product",
  "name": "{{PRODUCT_NAME}}",
  "description": "{{PRODUCT_DESCRIPTION}}",
  "image": ["{{PRODUCT_IMAGE_1}}", "{{PRODUCT_IMAGE_2}}"],
  "sku": "{{SKU}}",
  "mpn": "{{MPN}}",
  "gtin13": "{{GTIN13}}",
  "brand": {
    "@type": "Brand",
    "name": "{{BRAND_NAME}}"
  },
  "category": "{{PRODUCT_CATEGORY}}",
  "color": "{{PRODUCT_COLOR}}",
  "material": "{{PRODUCT_MATERIAL}}",
  "offers": {
    "@type": "Offer",
    "url": "{{PRODUCT_URL}}",
    "price": "{{PRODUCT_PRICE}}",
    "priceCurrency": "TWD",
    "priceValidUntil": "{{PRICE_VALID_UNTIL}}",
    "availability": "https://schema.org/{{AVAILABILITY_STATUS}}",
    "itemCondition": "https://schema.org/NewCondition",
    "seller": {
      "@type": "Organization",
      "name": "{{SELLER_NAME}}"
    },
    "shippingDetails": {
      "@type": "OfferShippingDetails",
      "shippingRate": {
        "@type": "MonetaryAmount",
        "value": "{{SHIPPING_COST}}",
        "currency": "TWD"
      },
      "shippingDestination": {
        "@type": "DefinedRegion",
        "addressCountry": "TW"
      },
      "deliveryTime": {
        "@type": "ShippingDeliveryTime",
        "handlingTime": {
          "@type": "QuantitativeValue",
          "minValue": 1,
          "maxValue": 3,
          "unitCode": "DAY"
        },
        "transitTime": {
          "@type": "QuantitativeValue",
          "minValue": 1,
          "maxValue": 5,
          "unitCode": "DAY"
        }
      }
    }
  },
  "aggregateRating": {
    "@type": "AggregateRating",
    "ratingValue": "{{AVG_RATING}}",
    "ratingCount": "{{RATING_COUNT}}"
  },
  "review": [
    {
      "@type": "Review",
      "author": { "@type": "Person", "name": "{{REVIEWER_NAME}}" },
      "reviewRating": { "@type": "Rating", "ratingValue": "{{REVIEW_RATING}}" },
      "reviewBody": "{{REVIEW_BODY}}"
    }
  ]
}
```

**`AVAILABILITY_STATUS` 可選值**：
- `InStock`：有庫存
- `OutOfStock`：缺貨
- `PreOrder`：預購中
- `LimitedAvailability`：限量

---

#### 17. LocalBusiness（在地商家 - 若為實體店家）

**判斷條件**：
- 頁面為店家介紹、服務據點
- 包含地址、營業時間、電話
- 有 Google Maps 嵌入或地圖資訊

```json
{
  "@type": "{{BUSINESS_TYPE}}",
  "@id": "{{CANONICAL_URL}}#localbusiness",
  "name": "{{BUSINESS_NAME}}",
  "description": "{{BUSINESS_DESCRIPTION}}",
  "image": "{{BUSINESS_IMAGE}}",
  "url": "{{BUSINESS_URL}}",
  "telephone": "{{BUSINESS_PHONE}}",
  "email": "{{BUSINESS_EMAIL}}",
  "priceRange": "{{PRICE_RANGE}}",
  "address": {
    "@type": "PostalAddress",
    "streetAddress": "{{STREET_ADDRESS}}",
    "addressLocality": "{{CITY}}",
    "addressRegion": "{{REGION}}",
    "postalCode": "{{POSTAL_CODE}}",
    "addressCountry": "TW"
  },
  "geo": {
    "@type": "GeoCoordinates",
    "latitude": "{{LATITUDE}}",
    "longitude": "{{LONGITUDE}}"
  },
  "openingHoursSpecification": [
    {
      "@type": "OpeningHoursSpecification",
      "dayOfWeek": ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"],
      "opens": "{{WEEKDAY_OPEN}}",
      "closes": "{{WEEKDAY_CLOSE}}"
    },
    {
      "@type": "OpeningHoursSpecification",
      "dayOfWeek": ["Saturday", "Sunday"],
      "opens": "{{WEEKEND_OPEN}}",
      "closes": "{{WEEKEND_CLOSE}}"
    }
  ],
  "hasMap": "{{GOOGLE_MAPS_URL}}",
  "aggregateRating": {
    "@type": "AggregateRating",
    "ratingValue": "{{AVG_RATING}}",
    "ratingCount": "{{RATING_COUNT}}"
  },
  "sameAs": ["{{FACEBOOK_URL}}", "{{INSTAGRAM_URL}}"]
}
```

**`BUSINESS_TYPE` 常見值**：

| 類型 | Schema Type | 範例 |
|------|-------------|------|
| 餐廳 | `Restaurant` | 餐館、咖啡廳 |
| 診所 | `MedicalClinic` | 牙醫、中醫診所 |
| 美容 | `BeautySalon` | 髮廊、美甲 |
| 健身 | `HealthClub` | 健身房、瑜珈教室 |
| 旅館 | `Hotel` | 飯店、民宿 |
| 汽修 | `AutoRepair` | 汽車保養、機車行 |
| 寵物 | `PetStore` | 寵物店、動物醫院 |
| 室內設計 | `HomeAndConstructionBusiness` | 設計公司、裝修工作室 |

**`PRICE_RANGE` 建議值**：
- `$`：平價（500 以下）
- `$$`：中等（500-1500）
- `$$$`：較高（1500-3000）
- `$$$$`：高價（3000 以上）

---

### 條件式 Schema 動態判斷規則

| Schema | 關鍵字/特徵偵測 | 優先級 |
|--------|----------------|--------|
| **HowTo** | 「步驟」「教學」「怎麼做」「DIY」+ 編號清單 | 高 |
| **Recipe** | 「食譜」「做法」「材料」+ 食材清單 | 高 |
| **VideoObject** | YouTube/Vimeo 嵌入、`<video>` 標籤 | 高 |
| **ItemList** | 「N 大」「排行」「推薦清單」+ 編號清單 | 中 |
| **Table** | `<table>` 標籤、比較表格 | 中 |
| **Review** | 「評測」「開箱」「心得」+ 星級評分 | 中 |
| **Product** | 價格、SKU、「加入購物車」按鈕 | 中 |
| **Event** | 日期 + 時間 + 地點 + 報名連結 | 中 |
| **Course** | 「課程」「學習」+ 時數 + 報名 | 中 |
| **LocalBusiness** | 地址 + 電話 + 營業時間 + Google Maps | 中 |

---

## 二、SGE/AEO 標記規範

### HTML Class 標記（5 種）

| 標記 | CSS Class | data 屬性 | 用途 | 範例 |
|------|-----------|----------|------|------|
| **關鍵答案** | `.key-answer` | `data-question="搜尋問句"` | 每個 H2 開頭的直接答案 | `<p class="key-answer" data-question="如何選擇油漆">建議選擇...</p>` |
| **重點摘要** | `.key-takeaway` | - | 文章核心要點（2-3 個） | `<div class="key-takeaway">重點：...</div>` |
| **專家引言** | `.expert-quote` | - | 帶署名的引用（至少 1 個） | `<blockquote class="expert-quote">...</blockquote>` |
| **行動步驟** | `.actionable-steps` | - | 可執行的步驟清單 | `<ol class="actionable-steps">...</ol>` |
| **比較表格** | `.comparison-table` | - | 結構化比較資訊 | `<table class="comparison-table">...</table>` |

### .key-answer 使用規則

1. **每個 H2 段落開頭**必須有一個 `.key-answer`
2. **必須包含 data-question 屬性**，值為該段落回答的搜尋問句
3. **內容必須是直接答案**，不超過 2 句話

```html
<h2>如何判斷油漆是否安全？</h2>
<p class="key-answer" data-question="如何判斷油漆是否安全">
  <strong>查看 VOC 含量標示</strong>，選擇低於 50g/L 的產品即為安全油漆。
</p>
```

### Speakable 選擇器（7 個）

以下 CSS 選擇器會被 Google 語音搜尋抓取：

```json
"speakable": {
  "cssSelector": [
    ".article-summary",
    ".speakable-content",
    ".key-takeaway",
    ".key-answer",
    ".expert-quote",
    ".actionable-steps li",
    ".faq-answer-content"
  ]
}
```

---

## 三、E-E-A-T 信號要求

### Person Schema 必填欄位

```json
{
  "knowsAbout": ["專長1", "專長2", "專長3"],
  "hasCredential": [{
    "@type": "EducationalOccupationalCredential",
    "name": "認證名稱",
    "credentialCategory": "Professional Certificate"
  }],
  "alumniOf": { "@type": "Organization", "name": "學歷/經歷" },
  "sameAs": ["社群連結1", "社群連結2"]
}
```

### 權威來源連結要求

文章必須包含至少 2 個高權威外部連結：

| 優先級 | 來源類型 | 範例 |
|--------|----------|------|
| **1** | 政府機構 | .gov.tw、衛福部、環保署 |
| **2** | 學術期刊 | PubMed、DOI 連結 |
| **3** | 產業協會 | 認證機構、專業協會 |

---

## 四、YMYL 內容專屬欄位

**適用類型**：健康、醫療、財務、法律

| 欄位 | 說明 | 格式 |
|------|------|------|
| `lastReviewed` | 最後審核日期 | ISO 8601（如 2025-02-12） |
| `reviewedBy` | 審核者資訊 | Person 名稱 + 資格 |
| `expiration_date` | 內容過期時間 | ISO 8601（建議 2 年內） |
| `financialReviewStatus` | 財務內容審核狀態 | reviewed / pending / not-applicable |

### lastReviewed 使用情境

| 情境 | 說明 | 更新頻率 |
|------|------|---------|
| **首次發布** | 發布時設定為當日 | 一次性 |
| **內容更新** | 有實質內容變動時更新 | 每次修改 |
| **法規變動** | 相關法規修正時重新審核 | 視法規變動 |
| **定期審核** | 無變動但定期確認正確性 | 每 6-12 個月 |

### YMYL 免責聲明

**醫療類**：
> 本文內容僅供參考，不能取代專業醫療建議。如有健康問題，請諮詢合格醫療人員。

**財務類**：
> 本文內容僅供參考，不構成投資建議。投資有風險，請審慎評估自身財務狀況。

**法律類**：
> 本文內容僅供一般性參考，不構成法律意見。具體法律問題請諮詢專業律師。

---

## 五、SEO 檢查清單

### 關鍵字優化

- [ ] 標題（H1/title）包含核心關鍵字
- [ ] 第一段（前 100 字）包含關鍵字
- [ ] H2 標題自然融入關鍵字
- [ ] 關鍵字密度 2-3%
- [ ] 包含 3-5 個 LSI 語意相關詞

### 結構優化

- [ ] H1 唯一且包含關鍵字
- [ ] H2 數量 4-6 個
- [ ] 段落長度 150-300 字
- [ ] 總字數 2000+ 字

### 連結優化

- [ ] 內部連結 5+ 個（錨點使用關鍵字）
- [ ] 外部權威連結 2+ 個
- [ ] 無斷裂連結

### 圖片優化

- [ ] 所有圖片有 alt 文字
- [ ] 首屏圖片 `loading="eager"`
- [ ] 非首屏圖片 `loading="lazy"`
- [ ] 圖片尺寸明確（width/height 屬性）

### Core Web Vitals 優化

- [ ] 外部字體使用 `preconnect` 提示
- [ ] 關鍵資源使用 `preload` 提示
- [ ] 首屏內容優先載入

```html
<!-- preconnect 範例 -->
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>

<!-- preload 範例 -->
<link rel="preload" href="/fonts/main.woff2" as="font" type="font/woff2" crossorigin>
```

### URL 優化

- [ ] URL slug 使用英文小寫
- [ ] URL slug 使用連字號（-）分隔單詞
- [ ] URL slug 包含核心關鍵字
- [ ] URL slug 長度適中（3-5 個單詞）
- [ ] 避免特殊字元和中文（除非必要）

```
良好範例：/article/safe-paint-for-children-room
不佳範例：/article/兒童房油漆安全
不佳範例：/article/safe_paint_for_children_room_2024_updated
```

---

## 六、Meta 標籤規範

### 基本標籤

```html
<title>{{TITLE}}（含關鍵字，60字內）</title>
<meta name="description" content="{{DESCRIPTION}}（155字內，含關鍵字）" />
<link rel="canonical" href="{{CANONICAL_URL}}" />
```

### Open Graph 標籤

```html
<meta property="og:title" content="{{TITLE}}" />
<meta property="og:description" content="{{DESCRIPTION}}" />
<meta property="og:image" content="{{OG_IMAGE}}" />
<meta property="og:url" content="{{CANONICAL_URL}}" />
<meta property="og:type" content="article" />
<meta property="og:site_name" content="{{SITE_NAME}}" />
<meta property="article:published_time" content="{{PUBLISHED_DATE}}" />
<meta property="article:modified_time" content="{{MODIFIED_DATE}}" />
<meta property="article:author" content="{{AUTHOR_NAME}}" />
```

### Twitter Card 標籤

```html
<meta name="twitter:card" content="summary_large_image" />
<meta name="twitter:title" content="{{TITLE}}" />
<meta name="twitter:description" content="{{DESCRIPTION}}" />
<meta name="twitter:image" content="{{OG_IMAGE}}" />
```

### 圖片規格

| 用途 | 尺寸 | 格式 |
|------|------|------|
| OG Image | 1200 x 630 px | JPG/PNG |
| Twitter Image | 1200 x 628 px | JPG/PNG |

---

## 七、元資料欄位

### 完整元資料結構

```json
{
  "topic": {
    "primary_topic": "主要主題",
    "article_category": "分類",
    "article_section": "章節",
    "article_tags": ["標籤1", "標籤2", "標籤3", "標籤4", "標籤5"]
  },
  "breadcrumb": {
    "category": "分類名稱",
    "category_url": "/category/xxx"
  },
  "content_stats": {
    "word_count": 2500,
    "reading_time": "8 分鐘",
    "paragraph_count": 12,
    "heading_count": 6
  },
  "dates": {
    "published_date": "2025-02-12",
    "published_date_display": "2025 年 2 月 12 日",
    "modified_date": "2025-02-12",
    "modified_date_display": "2025 年 2 月 12 日",
    "expiration_date": "2027-02-12"
  },
  "images": {
    "og_image": "https://...",
    "og_image_alt": "圖片描述",
    "hero_image": "https://...",
    "image_credit": "Photo by Pexels",
    "image_license_url": "https://www.pexels.com/license/"
  },
  "urls": {
    "canonical_url": "https://...",
    "canonical_url_encoded": "https%3A%2F%2F...",
    "title_encoded": "%E6%A8%99%E9%A1%8C..."
  },
  "citations": {
    "citations": [
      {
        "title": "研究標題",
        "url": "https://doi.org/...",
        "source": "期刊名稱",
        "year": 2024
      }
    ],
    "significant_links": [
      "https://example.com/related-article-1",
      "https://example.com/related-article-2"
    ]
  },
  "fact_check": {
    "fact_check_claim": null,
    "medical_disclaimer": "本文內容僅供參考...",
    "financial_disclaimer": null
  }
}
```

### 標籤數量規則

- `article_tags`：必須 5-8 個標籤
- 標籤必須與文章內容相關
- 避免過度寬泛或過度狹窄的標籤

### 文章來源資訊

```json
{
  "article_source": {
    "type": "original | repost | interview | scholar_contribution",
    "source_organization": "來源組織名稱",
    "editor": "總編輯",
    "reporter": "記者名（若為採訪報導）",
    "interviewee": "受訪者（若為採訪報導）"
  }
}
```

**來源類型說明**：
- `original`：原創內容
- `repost`：協會/組織轉載
- `interview`：記者採訪報導
- `scholar_contribution`：學者投稿

---

## 八、JSON-LD 整合格式

所有 Schema 必須使用 `@graph` 整合：

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@graph": [
    { "@type": "WebPage", ... },
    { "@type": "Article", ... },
    { "@type": "Person", ... },
    { "@type": "Organization", ... },
    { "@type": "BreadcrumbList", ... },
    { "@type": "FAQPage", ... },
    { "@type": "ImageObject", ... }
  ]
}
</script>
```

### @id 互相連結規則

#### 必填 Schema

| Schema | @id 格式 | 被引用於 |
|--------|----------|---------|
| WebPage | `{{URL}}#webpage` | Article.mainEntityOfPage |
| Article | `{{URL}}#article` | - |
| Person | `{{AUTHOR_URL}}#person` | Article.author |
| Organization | `{{SITE_URL}}#organization` | Article.publisher |
| ImageObject | `{{URL}}#primaryimage` | WebPage.primaryImageOfPage |

#### 條件式 Schema

| Schema | @id 格式 | 說明 |
|--------|----------|------|
| HowTo | `{{URL}}#howto` | 步驟教學 |
| Recipe | `{{URL}}#recipe` | 食譜（多個時加編號 #recipe-1） |
| VideoObject | `{{URL}}#video` | 影片（多個時加編號 #video-1） |
| ItemList | `{{URL}}#itemlist` | 排序清單 |
| Table | `{{URL}}#table` | 比較表格 |
| Review | `{{URL}}#review` | 評測 |
| Product | `{{URL}}#product` | 商品 |
| Event | `{{URL}}#event` | 活動 |
| Course | `{{URL}}#course` | 課程 |
| LocalBusiness | `{{URL}}#localbusiness` | 店家

---

## 九、驗證方式

### Google Rich Results Test

將完成的 JSON-LD 貼入以下工具驗證：
https://search.google.com/test/rich-results

### 預期通過項目

- [ ] Article
- [ ] BreadcrumbList
- [ ] FAQPage
- [ ] HowTo（若適用）
- [ ] Recipe（若適用）
- [ ] VideoObject（若適用）

---

## 十、常見錯誤清單

| 錯誤 | 說明 | 修正方式 |
|------|------|---------|
| 缺少 speakable | WebPage 沒有 speakable 欄位 | 加入 7 個 cssSelector |
| @id 格式錯誤 | 沒有使用 `#` 分隔符 | 使用 `{{URL}}#type` 格式 |
| Person 缺少 hasCredential | 沒有認證資訊 | 加入至少 1 個 credential |
| FAQPage 數量不足 | 少於 3 個 Q&A | 補充到 3-5 個 |
| 日期格式錯誤 | 沒有使用 ISO 8601 | 使用 YYYY-MM-DD 格式 |
| 圖片缺少 license | ImageObject 沒有授權資訊 | 加入 license 和 creditText |
| OG 圖片尺寸錯誤 | 不是 1200x630 | 調整圖片尺寸 |
| description 過長 | 超過 155 字 | 精簡到 155 字內 |

---

## 附錄：快速參考卡

### 必填 Schema 清單
1. WebPage（含 Speakable）
2. Article（含 SearchAction）
3. Person（含 hasCredential）
4. Organization（含 contactPoint）
5. BreadcrumbList
6. FAQPage（3-5 個 Q&A）
7. ImageObject（含 license）

### SGE 標記清單
1. `.key-answer`（含 data-question）
2. `.key-takeaway`
3. `.expert-quote`
4. `.actionable-steps`
5. `.comparison-table`

### E-E-A-T 欄位清單
1. `knowsAbout`（至少 2 個）
2. `hasCredential`（至少 1 個）
3. `sameAs`（至少 1 個）
4. `alumniOf`（選填）

### YMYL 欄位清單
1. `lastReviewed`
2. `reviewedBy`
3. `expiration_date`
4. 免責聲明
