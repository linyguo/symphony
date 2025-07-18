/*
 * Copyright (c) Microsoft Corporation.
 * Licensed under the MIT license.
 * SPDX-License-Identifier: MIT
 */

package model

import (
	"encoding/json"
	"errors"
	"fmt"
	"reflect"
	"strings"
	"time"

	"github.com/eclipse-symphony/symphony/coa/pkg/apis/v1alpha2"
)

type CampaignState struct {
	ObjectMeta ObjectMeta    `json:"metadata,omitempty"`
	Spec       *CampaignSpec `json:"spec,omitempty"`
}

type ActivationState struct {
	ObjectMeta ObjectMeta        `json:"metadata,omitempty"`
	Spec       *ActivationSpec   `json:"spec,omitempty"`
	Status     *ActivationStatus `json:"status,omitempty"`
}

// +kubebuilder:validation:Enum=stopOnAnyFailure;stopOnNFailures;silentlyContinue;
type ErrorActionMode string

const (
	ErrorActionMode_StopOnAnyFailure ErrorActionMode = "stopOnAnyFailure"
	ErrorActionMode_StopOnNFailures  ErrorActionMode = "stopOnNFailures"
	ErrorActionMode_SilentlyContinue ErrorActionMode = "silentlyContinue"
)

func (e ErrorActionMode) String() string {
	return string(e)
}

func (e ErrorActionMode) IsStopOnAnyFailure() bool {
	return strings.EqualFold(e.String(), ErrorActionMode_StopOnAnyFailure.String())
}

func (e ErrorActionMode) IsStopOnNFailures() bool {
	return strings.EqualFold(e.String(), ErrorActionMode_StopOnNFailures.String())
}

func (e ErrorActionMode) IsSilentlyContinue() bool {
	return strings.EqualFold(e.String(), ErrorActionMode_SilentlyContinue.String())
}

// +kubebuilder:object:generate=true
type ErrorAction struct {
	Mode                 ErrorActionMode `json:"mode,omitempty"`
	MaxToleratedFailures int             `json:"maxToleratedFailures,omitempty"`
}

// +Kubebuilder:object:generate=true
type TaskOption struct {
	Concurrency int         `json:"concurrency,omitempty"`
	ErrorAction ErrorAction `json:"errorAction,omitempty"`
}

type TaskSpec struct {
	Name     string                 `json:"name,omitempty"`
	Provider string                 `json:"provider,omitempty"`
	Config   interface{}            `json:"config,omitempty"`
	Inputs   map[string]interface{} `json:"inputs,omitempty"`
	Target   string                 `json:"target,omitempty"`
}

type StageSpec struct {
	Name          string                 `json:"name,omitempty"`
	Contexts      string                 `json:"contexts,omitempty"`
	Provider      string                 `json:"provider,omitempty"`
	Config        interface{}            `json:"config,omitempty"`
	StageSelector string                 `json:"stageSelector,omitempty"`
	Inputs        map[string]interface{} `json:"inputs,omitempty"`
	HandleErrors  bool                   `json:"handleErrors,omitempty"`
	Schedule      string                 `json:"schedule,omitempty"`
	Target        string                 `json:"target,omitempty"`
	Tasks         []TaskSpec             `json:"tasks,omitempty"`
	TaskOption    TaskOption             `json:"taskOption,omitempty"`
}

// UnmarshalJSON customizes the JSON unmarshalling for StageSpec
func (s *StageSpec) UnmarshalJSON(data []byte) error {
	type Alias StageSpec
	aux := &struct {
		*Alias
	}{
		Alias: (*Alias)(s),
	}
	if err := json.Unmarshal(data, &aux); err != nil {
		return err
	}
	// validate if Schedule meet RFC 3339
	if s.Schedule != "" {
		if _, err := time.Parse(time.RFC3339, s.Schedule); err != nil {
			return v1alpha2.NewCOAError(nil, fmt.Sprintf("invalid timestamp format: %v", err), v1alpha2.BadConfig)
		}
	}
	return nil
}

// MarshalJSON customizes the JSON marshalling for StageSpec
func (s StageSpec) MarshalJSON() ([]byte, error) {
	type Alias StageSpec
	if s.Schedule != "" {
		if _, err := time.Parse(time.RFC3339, s.Schedule); err != nil {
			return nil, v1alpha2.NewCOAError(nil, fmt.Sprintf("invalid timestamp format: %v", err), v1alpha2.BadConfig)
		}
	}
	return json.Marshal(&struct {
		*Alias
	}{
		Alias: (*Alias)(&s),
	})
}

func (s StageSpec) DeepEquals(other IDeepEquals) (bool, error) {
	otherS, ok := other.(StageSpec)
	if !ok {
		return false, errors.New("parameter is not a StageSpec type")
	}

	if s.Name != otherS.Name {
		return false, nil
	}

	if s.Provider != otherS.Provider {
		return false, nil
	}

	if !reflect.DeepEqual(s.Config, otherS.Config) {
		return false, nil
	}

	if s.StageSelector != otherS.StageSelector {
		return false, nil
	}

	if !reflect.DeepEqual(s.Inputs, otherS.Inputs) {
		return false, nil
	}

	if !reflect.DeepEqual(s.Schedule, otherS.Schedule) {
		return false, nil
	}

	return true, nil
}

type ActivationStatus struct {
	ActivationGeneration string         `json:"activationGeneration,omitempty"`
	UpdateTime           string         `json:"updateTime,omitempty"`
	Status               v1alpha2.State `json:"status,omitempty"`
	StatusMessage        string         `json:"statusMessage,omitempty"`
	StageHistory         []StageStatus  `json:"stageHistory,omitempty"`
}
type StageStatus struct {
	Stage         string                 `json:"stage,omitempty"`
	NextStage     string                 `json:"nextStage,omitempty"`
	Inputs        map[string]interface{} `json:"inputs,omitempty"`
	Outputs       map[string]interface{} `json:"outputs,omitempty"`
	Status        v1alpha2.State         `json:"status,omitempty"`
	IsActive      bool                   `json:"isActive,omitempty"`
	StatusMessage string                 `json:"statusMessage,omitempty"`
	ErrorMessage  string                 `json:"errorMessage,omitempty"`
}

type ActivationSpec struct {
	Campaign string                 `json:"campaign,omitempty"`
	Stage    string                 `json:"stage,omitempty"`
	Inputs   map[string]interface{} `json:"inputs,omitempty"`
}

func (c ActivationSpec) DeepEquals(other IDeepEquals) (bool, error) {
	otherC, ok := other.(ActivationSpec)
	if !ok {
		return false, errors.New("parameter is not a ActivationSpec type")
	}

	if c.Campaign != otherC.Campaign {
		return false, errors.New("campaign doesn't match")
	}

	if c.Stage != otherC.Stage {
		return false, errors.New("stage doesn't match")
	}

	if !reflect.DeepEqual(c.Inputs, otherC.Inputs) {
		return false, errors.New("inputs doesn't match")
	}

	return true, nil
}
func (c ActivationState) DeepEquals(other IDeepEquals) (bool, error) {
	otherC, ok := other.(ActivationState)
	if !ok {
		return false, errors.New("parameter is not a ActivationState type")
	}

	equal, err := c.ObjectMeta.DeepEquals(otherC.ObjectMeta)
	if err != nil || !equal {
		return equal, err
	}

	equal, err = c.Spec.DeepEquals(*otherC.Spec)
	if err != nil || !equal {
		return equal, err
	}
	return true, nil
}

type CampaignSpec struct {
	FirstStage   string               `json:"firstStage,omitempty"`
	Stages       map[string]StageSpec `json:"stages,omitempty"`
	SelfDriving  bool                 `json:"selfDriving,omitempty"`
	Version      string               `json:"version,omitempty"`
	RootResource string               `json:"rootResource,omitempty"`
}

func (c CampaignSpec) DeepEquals(other IDeepEquals) (bool, error) {
	otherC, ok := other.(CampaignSpec)
	if !ok {
		return false, errors.New("parameter is not a CampaignSpec type")
	}

	if c.FirstStage != otherC.FirstStage {
		return false, nil
	}

	if c.SelfDriving != otherC.SelfDriving {
		return false, nil
	}

	if len(c.Stages) != len(otherC.Stages) {
		return false, nil
	}

	for i, stage := range c.Stages {
		otherStage := otherC.Stages[i]

		if eq, err := stage.DeepEquals(otherStage); err != nil || !eq {
			return eq, err
		}
	}

	return true, nil
}
func (c CampaignState) DeepEquals(other IDeepEquals) (bool, error) {
	otherC, ok := other.(CampaignState)
	if !ok {
		return false, errors.New("parameter is not a CampaignState type")
	}

	equal, err := c.ObjectMeta.DeepEquals(otherC.ObjectMeta)
	if err != nil || !equal {
		return equal, err
	}

	equal, err = c.Spec.DeepEquals(*otherC.Spec)
	if err != nil || !equal {
		return equal, err
	}

	return true, nil
}
