---
title: "Fixing header and footer overlap on WordPress checkout pages (EDD + block theme)"
date: 2026-03-07T12:00:00Z
draft: false
description: "EDD checkout content hidden under sticky header? Fix header and footer overlap on block theme checkout pages with padding and scroll-margin."
tags: ["WordPress", "EDD", "block theme", "CSS", "checkout"]
---

We sell downloadable travel itineraries on [joyofexploringtheworld.com](https://joyofexploringtheworld.com/) using Easy Digital Downloads (EDD). With a sticky header and a block theme (Bricksy Pro), the checkout and receipt pages had content sitting under the header and footer. Here's how we fixed it.

## The problem

With a sticky or fixed header, the main content area starts at the top of the viewport. The header overlays it, so the first lines of the checkout form are hidden. Similarly, a fixed footer can cover the bottom of the page. FSE block themes don't always add padding for fixed elements on custom post types like EDD checkout.

## How to fix it

### 1. Identify the layout

Check whether your theme uses a fixed or sticky header. Inspect the main content wrapper—often `main` or a div with a content class. Note the header height (e.g. 80px).

### 2. Add padding-top to the main content

Add `padding-top` to the main or content wrapper equal to the header height. For example:

```css
main {
  padding-top: 80px; /* match header height */
}
```

Or use `scroll-margin-top` if you need anchor targets (e.g. form validation) to scroll into view without being hidden:

```css
main {
  scroll-margin-top: 80px;
}
```

### 3. Add padding-bottom for the footer

If the footer is fixed, add `padding-bottom` to the main content so the last elements aren't covered:

```css
main {
  padding-bottom: 120px; /* match footer height */
}
```

### 4. Check theme global styles and block templates

In a block theme, layout is often defined in global styles or block templates. Look for the template that wraps the main content and add the padding there, or use Additional CSS in the Customizer. EDD may use its own templates—check for EDD-specific overrides.

```css
/* Add padding to account for fixed header height */
.wp-site-blocks > main,
.wp-site-blocks > .is-layout-flow {
  padding-top: 80px;   /* match your header height */
  padding-bottom: 60px; /* match your footer height */
}

/* For anchor targets, prevent them hiding behind the header */
[id] {
  scroll-margin-top: 100px;
}
```

### 5. Test on all relevant pages

Verify the fix on:

- Checkout page
- Receipt / confirmation page
- Order history or other EDD pages

## What you can do

- Measure your header and footer heights
- Add matching `padding-top` and `padding-bottom` to the main content
- Use `scroll-margin-top` if anchors need to scroll into view
- Test on checkout, receipt, and confirmation flows

Fixed headers need matching content offsets; FSE themes may not add them by default for custom post types like EDD checkout. A small CSS change fixes the overlap and improves the checkout experience.

**See also**: [Running a WordPress Travel Blog on a Budget VPS: The Full Stack](/posts/wordpress-docker-compose-production-stack/)

{{< cta >}}
