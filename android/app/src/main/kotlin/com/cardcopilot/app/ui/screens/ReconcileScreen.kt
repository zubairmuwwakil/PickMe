package com.cardcopilot.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cardcopilot.store.CategoryMapper
import com.cardcopilot.store.db.PredictionRecord
import com.cardcopilot.store.models.MissClass
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReconcileScreen(
    unreconciledRecords: List<PredictionRecord>,
    availableCategories: List<String>,
    onConfirmReconciliation: (purchaseId: String, observedCategory: String, rewardUnits: Double?, missClass: MissClass?) -> Unit,
    onBack: () -> Unit
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Reconcile Ritual", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background
                )
            )
        }
    ) { padding ->
        if (unreconciledRecords.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        Icons.Default.CheckCircle,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.height(48.dp)
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                    Text(
                        text = "All checkouts reconciled!",
                        fontWeight = FontWeight.Bold,
                        fontSize = 18.sp
                    )
                    Text(
                        text = "New checkouts will appear here for statement verification.",
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                item {
                    Text(
                        text = "Match your posted statement transactions to measure prediction accuracy.",
                        fontSize = 14.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                items(unreconciledRecords) { record ->
                    ReconcileCard(
                        record = record,
                        availableCategories = availableCategories,
                        onConfirm = { cat, units, miss ->
                            val purchaseId = record.purchaseWithObservation?.purchase?.id
                            if (purchaseId != null) {
                                onConfirmReconciliation(purchaseId, cat, units, miss)
                            }
                        }
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReconcileCard(
    record: PredictionRecord,
    availableCategories: List<String>,
    onConfirm: (category: String, units: Double?, miss: MissClass?) -> Unit
) {
    val prediction = record.prediction
    val purchase = record.purchaseWithObservation?.purchase

    var selectedCategory by remember { mutableStateOf(prediction.predictedCategory) }
    var rewardUnitsString by remember { mutableStateOf(prediction.predictedRewardUnits?.toString() ?: "") }
    var selectedMissClass by remember { mutableStateOf<MissClass?>(null) }
    var categoryDropdownExpanded by remember { mutableStateOf(false) }
    var missDropdownExpanded by remember { mutableStateOf(false) }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(MaterialTheme.colorScheme.surface)
            .padding(16.dp)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = prediction.merchantName,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = String.format(Locale.US, "$%.2f", purchase?.amountCad ?: prediction.scoredAmountCad ?: 0.0),
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary
                )
            }

            Text(
                text = "Predicted: ${CategoryMapper.categoryDisplayName(prediction.predictedCategory)} on ${prediction.winnerCardId}",
                fontSize = 13.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            // Category selector
            ExposedDropdownMenuBox(
                expanded = categoryDropdownExpanded,
                onExpandedChange = { categoryDropdownExpanded = it }
            ) {
                OutlinedTextField(
                    value = CategoryMapper.categoryDisplayName(selectedCategory),
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Posted Statement Category") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = categoryDropdownExpanded) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .menuAnchor()
                )
                ExposedDropdownMenu(
                    expanded = categoryDropdownExpanded,
                    onDismissRequest = { categoryDropdownExpanded = false }
                ) {
                    availableCategories.forEach { cat ->
                        DropdownMenuItem(
                            text = { Text(CategoryMapper.categoryDisplayName(cat)) },
                            onClick = {
                                selectedCategory = cat
                                categoryDropdownExpanded = false
                                if (cat != prediction.predictedCategory && selectedMissClass == null) {
                                    selectedMissClass = MissClass.WRONG_CATEGORY
                                } else if (cat == prediction.predictedCategory && selectedMissClass == MissClass.WRONG_CATEGORY) {
                                    selectedMissClass = null
                                }
                            }
                        )
                    }
                }
            }

            // Reward units
            OutlinedTextField(
                value = rewardUnitsString,
                onValueChange = { rewardUnitsString = it },
                label = { Text("Posted Reward Units (Points / Dollars)") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            // Miss Class selector
            ExposedDropdownMenuBox(
                expanded = missDropdownExpanded,
                onExpandedChange = { missDropdownExpanded = it }
            ) {
                OutlinedTextField(
                    value = selectedMissClass?.rawValue ?: "None (Prediction was correct)",
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Miss Taxonomy") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = missDropdownExpanded) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .menuAnchor()
                )
                ExposedDropdownMenu(
                    expanded = missDropdownExpanded,
                    onDismissRequest = { missDropdownExpanded = false }
                ) {
                    DropdownMenuItem(
                        text = { Text("None (Prediction was correct)") },
                        onClick = {
                            selectedMissClass = null
                            missDropdownExpanded = false
                        }
                    )
                    MissClass.entries.forEach { miss ->
                        DropdownMenuItem(
                            text = { Text(miss.rawValue) },
                            onClick = {
                                selectedMissClass = miss
                                missDropdownExpanded = false
                            }
                        )
                    }
                }
            }

            Button(
                onClick = {
                    val units = rewardUnitsString.toDoubleOrNull()
                    onConfirm(selectedCategory, units, selectedMissClass)
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(48.dp),
                shape = RoundedCornerShape(10.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.primary
                )
            ) {
                Text("Confirm Statement Fact", fontWeight = FontWeight.Bold)
            }
        }
    }
}
