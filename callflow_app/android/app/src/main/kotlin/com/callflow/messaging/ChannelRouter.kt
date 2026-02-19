package com.callflow.messaging

import android.content.Context
import android.util.Log
import com.callflow.bridge.CallEventStreamHandler
import com.callflow.rules.LocalRuleEngine
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class ChannelRouter(
    private val context: Context,
    private val smsModule: SmsModule,
    private val ruleEngine: LocalRuleEngine
) {
    companion object {
        const val TAG = "ChannelRouter"
    }

    fun processCallEvent(eventJson: String) {
        try {
            val event = JSONObject(eventJson)
            val phone = event.optString("phone", "")
            val contactName = event.optString("contact_name", "")
            val direction = event.optString("direction", "")
            val durationSeconds = event.optInt("duration_seconds", 0)
            val eventId = event.optString("event_id", "")

            if (phone.isEmpty() || direction.isEmpty()) {
                Log.w(TAG, "Invalid event data: missing phone or direction")
                return
            }

            // Check if we should process this event
            val evaluation = ruleEngine.evaluate(phone, direction, contactName, context)
            if (!evaluation.shouldProcess) {
                Log.d(TAG, "Event skipped: ${evaluation.reason}")
                return
            }

            // Mark number as sent for unique-per-day
            ruleEngine.markSent(phone, context)

            val delayMs = (evaluation.delaySeconds * 1000).toLong()

            // Process after delay
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                dispatchMessages(
                    phone, contactName, direction, durationSeconds, eventId, evaluation
                )
            }, delayMs)
        } catch (e: Exception) {
            Log.e(TAG, "Error processing call event", e)
        }
    }

    private fun dispatchMessages(
        phone: String,
        contactName: String,
        direction: String,
        durationSeconds: Int,
        eventId: String,
        evaluation: LocalRuleEngine.RuleEvaluation
    ) {
        val now = Date()
        val dateFormat = SimpleDateFormat("dd/MM/yyyy", Locale.getDefault())
        val timeFormat = SimpleDateFormat("hh:mm a", Locale.getDefault())

        val variables = mapOf(
            "contact_name" to contactName.ifEmpty { phone },
            "business_name" to ruleEngine.getBusinessName(),
            "landing_url" to ruleEngine.getLandingUrl(),
            "phone_number" to phone,
            "call_duration" to formatDuration(durationSeconds),
            "date" to dateFormat.format(now),
            "time" to timeFormat.format(now)
        )

        // Build brace-wrapped variables for SMS template substitution
        val braceVariables = variables.mapKeys { "{${it.key}}" }

        // Send SMS if enabled
        if (evaluation.sendSMS && evaluation.smsTemplate != null) {
            val message = buildOutboundSmsMessage(
                template = evaluation.smsTemplate,
                variables = braceVariables
            )
            val imagePath = evaluation.smsImagePath?.trim().orEmpty()
            val outboundMessage = when {
                imagePath.isEmpty() -> message
                message.isBlank() -> imagePath
                else -> "$message\n$imagePath"
            }
            val simSlot = evaluation.smsSimSlot
            val parts = smsModule.getSmsParts(outboundMessage)
            val sendMethod = if (imagePath.isNotEmpty()) "sms_manager_link" else "sms_manager"

            // Emit message log at dispatch time so UI stats do not depend on SMS sent callback reliability.
            val queuedLogData = mapOf<String, Any?>(
                "type" to "message_log",
                "event_id" to eventId,
                "channel" to "sms",
                "status" to "queued",
                "send_method" to sendMethod,
                "sim_slot" to simSlot,
                "sms_parts" to parts,
                "error_message" to "",
                "sent_at" to System.currentTimeMillis()
            )
            CallEventStreamHandler.getInstance().sendMessageLog(queuedLogData)

            smsModule.sendSms(phone, outboundMessage, simSlot) { success, error ->
                if (!success) {
                    Log.e(TAG, "SMS send callback reported failure: $error")
                }
            }
        }
    }

    private fun substituteVariables(template: String, variables: Map<String, String>): String {
        var result = template
        variables.forEach { (key, value) ->
            result = result.replace(key, value)
        }
        return result
    }

    private fun buildOutboundSmsMessage(
        template: String,
        variables: Map<String, String>
    ): String {
        val substituted = substituteVariables(template, variables).trimEnd()
        val landingUrl = ruleEngine.getLandingUrl().trim()
        val shouldAppendUrl = ruleEngine.shouldAppendWebsiteUrlToSms()

        if (!shouldAppendUrl || landingUrl.isEmpty()) {
            return substituted
        }

        if (substituted.contains(landingUrl, ignoreCase = true)) {
            return substituted
        }

        return if (substituted.isBlank()) landingUrl else "$substituted\n$landingUrl"
    }

    private fun formatDuration(seconds: Int): String {
        val minutes = seconds / 60
        val secs = seconds % 60
        return if (minutes > 0) "${minutes}m ${secs}s" else "${secs}s"
    }
}
