// Keep aliases away from browser-local Auth state before Flutter initializes.
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const legacyPages = url.hostname === 'chairside-staging.pages.dev' ||
      url.hostname.endsWith('.chairside-staging.pages.dev');
    if (legacyPages || url.hostname === 'spicyself.com' ||
        (url.hostname === 'www.spicyself.com' && url.protocol !== 'https:')) {
      url.protocol = 'https:';
      url.hostname = 'www.spicyself.com';
      url.port = '';
      // Preserve OAuth query parameters and the path, without logging either.
      return Response.redirect(url.toString(), 308);
    }
    return env.ASSETS.fetch(request);
  },
};
