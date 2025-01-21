/*
 * Copyright (c) Microsoft Corporation.
 * Licensed under the MIT license.
 * SPDX-License-Identifier: MIT
 */

package v1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// EDIT THIS FILE!  THIS IS SCAFFOLDING FOR YOU TO OWN!
// NOTE: json tags are required.  Any new fields you add must have json tags for the fields to be serialized.

// InstanceHistorySpec defines the desired state of InstanceHistory
type InstanceHistorySpec struct {
	// INSERT ADDITIONAL SPEC FIELDS - desired state of cluster
	// Important: Run "make" to regenerate code after modifying this file

	// Foo is an example field of InstanceHistory. Edit instancehistory_types.go to remove/update
	Foo string `json:"foo,omitempty"`
}

// InstanceHistoryStatus defines the observed state of InstanceHistory
type InstanceHistoryStatus struct {
	// INSERT ADDITIONAL STATUS FIELD - define observed state of cluster
	// Important: Run "make" to regenerate code after modifying this file
}

//+kubebuilder:object:root=true
//+kubebuilder:subresource:status

// InstanceHistory is the Schema for the instancehistories API
type InstanceHistory struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   InstanceHistorySpec   `json:"spec,omitempty"`
	Status InstanceHistoryStatus `json:"status,omitempty"`
}

//+kubebuilder:object:root=true

// InstanceHistoryList contains a list of InstanceHistory
type InstanceHistoryList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []InstanceHistory `json:"items"`
}

func init() {
	SchemeBuilder.Register(&InstanceHistory{}, &InstanceHistoryList{})
}
