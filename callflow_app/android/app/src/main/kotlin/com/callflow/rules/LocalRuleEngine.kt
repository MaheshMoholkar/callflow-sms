package com.callflow.rules

import android.content.Context
import android.util.Log
import com.callflow.service.CallLogReader
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.concurrent.locks.ReentrantReadWriteLock
import kotlin.concurrent.read
import kotlin.concurrent.write

class LocalRuleEngine {

    companion object {
        const val TAG = "LocalRuleEngine"
        private const val PREFS_NAME = "callflow_rule_state"
        private const val PREFS_KEY_DATE = "sent_today_date"
        private const val PREFS_KEY_NUMBERS = "sent_today_numbers"
        private const val DEFAULT_PHONE_DIGITS = 10
    }

    data class TemplateData(val body: String, val imagePath: String?)

    data class RuleEvaluation(
        val shouldProcess: Boolean,
        val reason: String = "",
        val sendSMS: Boolean = false,
        val smsTemplate: String? = null,
        val smsImagePath: String? = null,
        val smsSimSlot: Int = 0,
        val delaySeconds: Int = 0
    )

    // Lock protecting config, templates, and sentToday from concurrent access
    private val lock = ReentrantReadWriteLock()

    private var config: JSONObject? = null
    private var businessName: String = ""
    private var landingUrl: String = ""
    private var appendWebsiteUrlToSms: Boolean = false
    private var planType: String = "none"
    private var planExpiresAt: Long = 0

    // Templates indexed by their ID
    private val templates = mutableMapOf<Long, TemplateData>()

    // Track numbers messaged today for unique-per-day feature
    private val sentToday = mutableSetOf<String>()
    private var sentTodayDate: String = ""

    fun updateConfig(configJson: String) {
        lock.write {
            try {
                val json = JSONObject(configJson)
                config = json.optJSONObject("rules")
                businessName = json.optString("business_name", "")
                landingUrl = json.optString("landing_url", "")
                appendWebsiteUrlToSms = json.optBoolean("append_website_url_to_sms", false)
                planType = json.optString("plan", "none")
                planExpiresAt = json.optLong("plan_expires_at", 0)

                // Load templates
                val templatesArray = json.optJSONArray("templates")
                if (templatesArray != null) {
                    templates.clear()
                    for (i in 0 until templatesArray.length()) {
                        val tmpl = templatesArray.getJSONObject(i)
                        val id = tmpl.optLong("id", 0)
                        val body = tmpl.optString("body", "")
                        val imagePath = if (tmpl.isNull("image_path")) null
                            else tmpl.optString("image_path", null)
                        if (id > 0 && body.isNotEmpty()) {
                            templates[id] = TemplateData(body, imagePath)
                        }
                    }
                }

                Log.d(TAG, "Rule config updated: sms=${config?.optJSONObject("sms")?.optBoolean("enabled", false)}")
            } catch (e: Exception) {
                Log.e(TAG, "Error parsing rule config", e)
            }
        }
    }

    fun getBusinessName(): String = lock.read { businessName }
    fun getLandingUrl(): String = lock.read { landingUrl }
    fun shouldAppendWebsiteUrlToSms(): Boolean = lock.read { appendWebsiteUrlToSms }

    fun markSent(phone: String, context: Context) {
        lock.write {
            val today = todayKey()
            syncSentToday(context, today)
            val normalizedPhone = normalizePhone(phone)
            if (normalizedPhone.isEmpty()) return@write
            sentToday.add(normalizedPhone)
            persistSentToday(context)
        }
    }

    fun evaluate(
        phone: String,
        direction: String,
        contactName: String,
        context: Context
    ): RuleEvaluation = lock.write {
        val ruleConfig = config ?: return@write RuleEvaluation(
            shouldProcess = false, reason = "No rule config"
        )

        // 1. Plan validity
        if (planType == "none") {
            return@write RuleEvaluation(shouldProcess = false, reason = "No active plan")
        }
        if (planExpiresAt > 0 && System.currentTimeMillis() > planExpiresAt) {
            return@write RuleEvaluation(shouldProcess = false, reason = "Plan expired")
        }

        // 3. Working hours
        val workingHours = ruleConfig.optJSONObject("working_hours")
        if (workingHours != null && workingHours.optBoolean("enabled", false)) {
            if (!isWithinWorkingHours(workingHours)) {
                return@write RuleEvaluation(shouldProcess = false, reason = "Outside working hours")
            }
        }

        // 4. Excluded numbers
        val excluded = ruleConfig.optJSONArray("excluded_numbers")
        if (excluded != null) {
            val cleanPhone = phone.replace(Regex("[^0-9]"), "")
            for (i in 0 until excluded.length()) {
                val excludedNum = excluded.optString(i, "").replace(Regex("[^0-9]"), "")
                if (excludedNum.isNotEmpty() && cleanPhone.endsWith(excludedNum)) {
                    return@write RuleEvaluation(
                        shouldProcess = false, reason = "Number excluded"
                    )
                }
            }
        }

        // 5. Unique per day
        val uniquePerDay = ruleConfig.optBoolean("unique_per_day", true)
        if (uniquePerDay) {
            val today = todayKey()
            syncSentToday(context, today)
            val cleanPhone = normalizePhone(phone)
            if (cleanPhone.isNotEmpty() && sentToday.contains(cleanPhone)) {
                return@write RuleEvaluation(
                    shouldProcess = false, reason = "Already messaged today"
                )
            }
        }

        // 6. Contact filter
        val contactFilter = ruleConfig.optJSONObject("contact_filter")
        if (contactFilter != null) {
            val mode = contactFilter.optString("mode", "all")
            if (mode != "all") {
                val isContact = CallLogReader().isContact(context, phone)
                if (mode == "contacts_only" && !isContact) {
                    return@write RuleEvaluation(
                        shouldProcess = false, reason = "Non-contact filtered"
                    )
                }
                if (mode == "non_contacts_only" && isContact) {
                    return@write RuleEvaluation(
                        shouldProcess = false, reason = "Contact filtered"
                    )
                }
            }
        }

        // 7. SMS channel
        val delaySeconds = ruleConfig.optInt("delay_seconds", 0)
        var sendSMS = false
        var smsTemplate: String? = null
        var smsImagePath: String? = null
        var smsSimSlot = 0

        val smsConfig = ruleConfig.optJSONObject("sms")
        if (smsConfig != null && smsConfig.optBoolean("enabled", false)) {
            if (planType == "sms") {
                smsSimSlot = ruleConfig.optInt("sms_sim_slot", 0)
                val templateId = getTemplateIdForDirection(smsConfig, direction)
                if (templateId != null) {
                    val templateData = templates[templateId]
                    smsTemplate = templateData?.body
                    smsImagePath = templateData?.imagePath
                    sendSMS = smsTemplate != null
                } else {
                    Log.d(TAG, "SMS: no template configured for $direction calls")
                }
            } else {
                Log.d(TAG, "SMS: plan '$planType' does not include SMS")
            }
        }

        if (!sendSMS) {
            return@write RuleEvaluation(
                shouldProcess = false,
                reason = "No SMS configured for $direction calls"
            )
        }

        return@write RuleEvaluation(
            shouldProcess = true,
            sendSMS = sendSMS,
            smsTemplate = smsTemplate,
            smsImagePath = smsImagePath,
            smsSimSlot = smsSimSlot,
            delaySeconds = delaySeconds
        )
    }

    private fun todayKey(): String {
        return SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(java.util.Date())
    }

    private fun normalizePhone(phone: String): String {
        val digits = phone.replace(Regex("[^0-9]"), "")
        if (digits.length <= DEFAULT_PHONE_DIGITS) return digits
        return digits.takeLast(DEFAULT_PHONE_DIGITS)
    }

    // Must be called with lock.write held.
    private fun syncSentToday(context: Context, today: String) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val storedDate = prefs.getString(PREFS_KEY_DATE, "") ?: ""

        if (storedDate != today) {
            sentToday.clear()
            sentTodayDate = today
            prefs.edit()
                .putString(PREFS_KEY_DATE, today)
                .putString(PREFS_KEY_NUMBERS, "[]")
                .apply()
            return
        }

        sentToday.clear()
        val raw = prefs.getString(PREFS_KEY_NUMBERS, "[]") ?: "[]"
        try {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val value = arr.optString(i, "")
                val normalized = normalizePhone(value)
                if (normalized.isNotEmpty()) {
                    sentToday.add(normalized)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse sent numbers cache", e)
        }
        sentTodayDate = today
    }

    // Must be called with lock.write held.
    private fun persistSentToday(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val arr = JSONArray()
        sentToday.forEach { arr.put(it) }
        prefs.edit()
            .putString(PREFS_KEY_DATE, sentTodayDate)
            .putString(PREFS_KEY_NUMBERS, arr.toString())
            .apply()
    }

    private fun getTemplateIdForDirection(
        channelConfig: JSONObject,
        direction: String
    ): Long? {
        val key = when (direction) {
            "incoming" -> "incoming_template_id"
            "outgoing" -> "outgoing_template_id"
            "missed" -> "missed_template_id"
            else -> return null
        }
        val id = channelConfig.optLong(key, 0)
        return if (id > 0) id else null
    }

    private fun isWithinWorkingHours(workingHours: JSONObject): Boolean {
        try {
            val startTime = workingHours.optString("start_time", "09:00")
            val endTime = workingHours.optString("end_time", "18:00")

            val timeFormat = SimpleDateFormat("HH:mm", Locale.getDefault())
            val now = Calendar.getInstance()

            val startCal = Calendar.getInstance().apply {
                time = timeFormat.parse(startTime) ?: return true
                set(Calendar.YEAR, now.get(Calendar.YEAR))
                set(Calendar.MONTH, now.get(Calendar.MONTH))
                set(Calendar.DAY_OF_MONTH, now.get(Calendar.DAY_OF_MONTH))
            }

            val endCal = Calendar.getInstance().apply {
                time = timeFormat.parse(endTime) ?: return true
                set(Calendar.YEAR, now.get(Calendar.YEAR))
                set(Calendar.MONTH, now.get(Calendar.MONTH))
                set(Calendar.DAY_OF_MONTH, now.get(Calendar.DAY_OF_MONTH))
            }

            return now.after(startCal) && now.before(endCal)
        } catch (e: Exception) {
            Log.e(TAG, "Error checking working hours", e)
            return true
        }
    }
}
