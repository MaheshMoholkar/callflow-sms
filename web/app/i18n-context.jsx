'use client';

import { createContext, useContext, useEffect, useMemo, useState } from 'react';
import { DEFAULT_LANG, SUPPORTED_LANGS, TRANSLATIONS } from './i18n';

const I18nContext = createContext(null);

function getPathValue(obj, path) {
  return path.split('.').reduce((acc, key) => {
    if (acc == null || typeof acc !== 'object') return undefined;
    return acc[key];
  }, obj);
}

export function I18nProvider({ children }) {
  const [language, setLanguage] = useState(DEFAULT_LANG);

  useEffect(() => {
    const pathname = window.location.pathname || '/';
    const isUserLandingPage = pathname.split('/').filter(Boolean).length === 1;

    if (isUserLandingPage) {
      setLanguage('mr');
      window.localStorage.setItem('adflow_lang', 'mr');
      return;
    }

    const stored = window.localStorage.getItem('adflow_lang');
    if (SUPPORTED_LANGS.includes(stored)) {
      setLanguage(stored);
    }
  }, []);

  useEffect(() => {
    document.documentElement.lang = language === 'mr' ? 'mr' : 'en';
    window.localStorage.setItem('adflow_lang', language);
  }, [language]);

  const value = useMemo(() => {
    const dictionary = TRANSLATIONS[language] || TRANSLATIONS[DEFAULT_LANG];

    const t = (path) => {
      const direct = getPathValue(dictionary, path);
      if (direct !== undefined) return direct;

      const fallback = getPathValue(TRANSLATIONS[DEFAULT_LANG], path);
      if (fallback !== undefined) return fallback;

      return path;
    };

    return {
      language,
      setLanguage,
      t,
    };
  }, [language]);

  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

export function useI18n() {
  const context = useContext(I18nContext);
  if (!context) {
    throw new Error('useI18n must be used within I18nProvider');
  }
  return context;
}
