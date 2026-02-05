import React, {useEffect, useState, useCallback} from 'react';
import {NavigationContainer} from '@react-navigation/native';
import {createStackNavigator} from '@react-navigation/stack';
import {createBottomTabNavigator} from '@react-navigation/bottom-tabs';
import {View, Text, StyleSheet, ActivityIndicator} from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';

import {colors} from '../theme';
import {RootStackParamList, MainTabParamList} from '../types';
import {onAuthStateChanged, signInAnonymously} from '../services/firebase';

// Screens
import WelcomeScreen from '../screens/Onboarding/WelcomeScreen';
import NameInputScreen from '../screens/Onboarding/NameInputScreen';
import SurgeryDateScreen from '../screens/Onboarding/SurgeryDateScreen';
import HomeScreen from '../screens/Home/HomeScreen';
import MeasureScreen from '../screens/Measure/MeasureScreen';
import HistoryScreen from '../screens/History/HistoryScreen';
import ProgressScreen from '../screens/Progress/ProgressScreen';

const Stack = createStackNavigator<RootStackParamList>();
const Tab = createBottomTabNavigator<MainTabParamList>();
const OnboardingStackNav = createStackNavigator();

const TabIcon = ({name, focused}: {name: string; focused: boolean}) => {
  const icons: {[key: string]: string} = {
    Home: '~',
    Measure: '+',
    History: '#',
    Progress: '^',
  };

  return (
    <View style={styles.tabIconContainer}>
      <Text
        style={[
          styles.tabIcon,
          {color: focused ? colors.primary : colors.textSecondary},
        ]}>
        {icons[name] || '?'}
      </Text>
      <Text
        style={[
          styles.tabLabel,
          {color: focused ? colors.primary : colors.textSecondary},
        ]}>
        {name}
      </Text>
    </View>
  );
};

const MainTabs = () => {
  return (
    <Tab.Navigator
      screenOptions={{
        headerShown: false,
        tabBarStyle: {
          backgroundColor: colors.surface,
          borderTopColor: colors.border,
          borderTopWidth: 0.5,
          height: 84,
          paddingBottom: 20,
          paddingTop: 10,
        },
        tabBarActiveTintColor: colors.primary,
        tabBarInactiveTintColor: colors.textSecondary,
        tabBarShowLabel: false,
      }}>
      <Tab.Screen
        name="Home"
        component={HomeScreen}
        options={{
          tabBarIcon: ({focused}) => <TabIcon name="Home" focused={focused} />,
        }}
      />
      <Tab.Screen
        name="Measure"
        component={MeasureScreen}
        options={{
          tabBarIcon: ({focused}) => (
            <TabIcon name="Measure" focused={focused} />
          ),
        }}
      />
      <Tab.Screen
        name="History"
        component={HistoryScreen}
        options={{
          tabBarIcon: ({focused}) => (
            <TabIcon name="History" focused={focused} />
          ),
        }}
      />
      <Tab.Screen
        name="Progress"
        component={ProgressScreen}
        options={{
          tabBarIcon: ({focused}) => (
            <TabIcon name="Progress" focused={focused} />
          ),
        }}
      />
    </Tab.Navigator>
  );
};

interface OnboardingStackProps {
  onComplete: () => void;
}

const OnboardingStack = ({onComplete}: OnboardingStackProps) => {
  return (
    <OnboardingStackNav.Navigator
      screenOptions={{
        headerShown: false,
        cardStyle: {backgroundColor: colors.background},
      }}>
      <OnboardingStackNav.Screen name="Welcome" component={WelcomeScreen} />
      <OnboardingStackNav.Screen name="NameInput" component={NameInputScreen} />
      <OnboardingStackNav.Screen name="SurgeryDate">
        {props => <SurgeryDateScreen {...props} onComplete={onComplete} />}
      </OnboardingStackNav.Screen>
    </OnboardingStackNav.Navigator>
  );
};

const AppNavigator = () => {
  const [isLoading, setIsLoading] = useState(true);
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [hasCompletedOnboarding, setHasCompletedOnboarding] = useState(false);

  const checkOnboarding = useCallback(async () => {
    const onboardingComplete = await AsyncStorage.getItem('onboardingComplete');
    setHasCompletedOnboarding(onboardingComplete === 'true');
  }, []);

  useEffect(() => {
    const initializeAuth = async () => {
      await checkOnboarding();

      const unsubscribe = onAuthStateChanged(async user => {
        if (user) {
          setIsAuthenticated(true);
        } else {
          try {
            await signInAnonymously();
            setIsAuthenticated(true);
          } catch (error) {
            console.error('Auth error:', error);
          }
        }
        setIsLoading(false);
      });

      return unsubscribe;
    };

    initializeAuth();
  }, [checkOnboarding]);

  const handleOnboardingComplete = useCallback(() => {
    setHasCompletedOnboarding(true);
  }, []);

  if (isLoading) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={colors.primary} />
      </View>
    );
  }

  return (
    <NavigationContainer>
      {!hasCompletedOnboarding ? (
        <OnboardingStack onComplete={handleOnboardingComplete} />
      ) : (
        <MainTabs />
      )}
    </NavigationContainer>
  );
};

const styles = StyleSheet.create({
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.background,
  },
  tabIconContainer: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  tabIcon: {
    fontSize: 24,
    fontWeight: '600',
  },
  tabLabel: {
    fontSize: 10,
    marginTop: 4,
  },
});

export default AppNavigator;
